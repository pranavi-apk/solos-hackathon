import AVFoundation
import Combine
import UIKit
#if !targetEnvironment(simulator)
import SolosAirGoSDK
#endif

/// Captures audio from the glasses mic (or phone mic fallback) and transcribes it
/// using Google Cloud Speech-to-Text.
///
/// VAD (Voice Activity Detection) is energy-based:
///   • Each buffer's RMS is checked against a low threshold.
///   • When speech energy is first detected, `hasCapturedSpeech` is set true.
///   • When vadSilenceTimeoutSeconds of low energy follows, the buffer is finalised
///     and sent to Google STT.
@MainActor
final class SpeechInputService: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var isListening = false
    @Published private(set) var isUsingGlassesMic = false
    @Published var errorMessage: String?

    var onFinalTranscript: ((String) -> Void)?
    var onBargeInDetected: (() -> Void)?

    // Google STT
    private let googleSTT = GoogleSTTService()

    // Energy-based VAD state
    private var hasCapturedSpeech = false
    private var lastSpeechAt: Date = .distantPast
    private var listenStartedAt: Date = .now
    private let speechEnergyThreshold: Float = 0.01   // below barge-in threshold

    private var vadSilenceTask: Task<Void, Never>?
    private let audioEngine = AVAudioEngine()
    private var isBargeInMonitoring = false
    private var bargeInMonitorStartedAt = Date.distantPast
    private var bargeInEnergeticBuffers = 0

    #if !targetEnvironment(simulator)
    private var glassesMicrophone: Microphone?
    private var glassesMicBridge: GlassesMicBridge?
    private var glassesMicOwner: GlassesMicOwner?
    #endif

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        if #available(iOS 17.0, *) {
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        } else {
            return await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    // MARK: - Glasses mic attachment

    #if !targetEnvironment(simulator)
    func attachGlassesMicrophone(_ microphone: Microphone?) {
        if let bridge = glassesMicBridge {
            glassesMicrophone?.removeListener(bridge)
        }
        glassesMicrophone = microphone
        if let microphone, let bridge = glassesMicBridge {
            microphone.addListener(bridge)
        }
    }
    #endif

    // MARK: - Start listening

    func startListening(
        allowPhoneFallback: Bool = false,
        micOwner: GlassesMicOwner = .coachSTT
    ) async throws {
        await releaseAudioCapture()
        transcript = ""
        errorMessage = nil
        isBargeInMonitoring = false
        bargeInEnergeticBuffers = 0
        hasCapturedSpeech = false
        lastSpeechAt = .distantPast
        listenStartedAt = .now
        googleSTT.reset()

        #if !targetEnvironment(simulator)
        if let glassesMicrophone {
            SoloChefLog.debug("stt: glasses mic owner=\(micOwner)")
            isUsingGlassesMic = true
            do {
                try await startGlassesListening(microphone: glassesMicrophone, owner: micOwner)
                return
            } catch {
                logGlassesError(error, context: "glasses mic start failed")
                await releaseGlassesMicrophone()
                guard allowPhoneFallback else { throw error }
                SoloChefLog.info("stt: falling back to phone mic")
                isUsingGlassesMic = false
                await waitForAudioSessionSettle()
                try startPhoneListening()
                return
            }
        }
        #endif

        SoloChefLog.debug("stt: phone mic")
        isUsingGlassesMic = false
        try startPhoneListening()
    }

    // MARK: - Barge-in monitoring (unchanged — energy-only, no STT)

    func startBargeInMonitoring() async {
        #if !targetEnvironment(simulator)
        guard let glassesMicrophone, !isListening, !isBargeInMonitoring else { return }
        guard !GlassesMicrophoneCoordinator.shared.isPassiveListenActive else {
            SoloChefLog.debug("stt: barge-in deferred — passive listen holds mic")
            return
        }

        await releaseGlassesMicrophone()

        SoloChefLog.debug("stt: barge-in monitor starting (glasses mic)")
        isBargeInMonitoring = true
        bargeInMonitorStartedAt = .now
        bargeInEnergeticBuffers = 0

        let bridge = GlassesMicBridge { [weak self] buffer in
            Task { @MainActor in
                self?.evaluateBargeInEnergy(buffer)
            }
        }
        glassesMicBridge = bridge
        glassesMicrophone.addListener(bridge)

        do {
            try await startGlassesMicrophone(
                microphone: glassesMicrophone,
                owner: .bargeInMonitor,
                context: "barge-in monitor"
            )
            SoloChefLog.debug("stt: barge-in monitor started")
        } catch {
            logGlassesError(error, context: "barge-in monitor start failed")
            await stopBargeInMonitoring()
        }
        #endif
    }

    func stopBargeInMonitoring() async {
        #if !targetEnvironment(simulator)
        guard isBargeInMonitoring else { return }
        isBargeInMonitoring = false
        bargeInEnergeticBuffers = 0

        if let bridge = glassesMicBridge, !isListening {
            glassesMicrophone?.removeListener(bridge)
            glassesMicBridge = nil
        }
        await releaseGlassesMicrophone()
        SoloChefLog.debug("stt: barge-in monitor stopped")
        #endif
    }

    // MARK: - Stop

    func stopListening() {
        finishListening(submit: false)
        #if !targetEnvironment(simulator)
        Task { await releaseGlassesMicrophone() }
        #endif
    }

    func stopListeningAndReleaseMic() async {
        finishListening(submit: false)
        #if !targetEnvironment(simulator)
        await releaseGlassesMicrophone()
        #endif
    }

    func stopAndSubmit() {
        Task { await finalizeAndSubmit() }
    }

    // MARK: - Audio session settle

    func waitForAudioSessionSettle(isSpeaking: @escaping () -> Bool = { false }) async {
        var waits = 0
        while isSpeaking(), waits < 50 {
            try? await Task.sleep(for: .milliseconds(100))
            waits += 1
        }
        try? await Task.sleep(for: .milliseconds(50))
    }

    // MARK: - Private: phone mic

    private func startPhoneListening() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.googleSTT.append(buffer)
            Task { @MainActor in
                self.trackSpeechEnergy(buffer)
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        isListening = true
        startVADTimer()
        SoloChefLog.debug("stt: phone mic started sampleRate=\(format.sampleRate)")
    }

    // MARK: - Private: glasses mic

    #if !targetEnvironment(simulator)
    private func startGlassesListening(microphone: Microphone, owner: GlassesMicOwner) async throws {
        prepareAudioSessionForGlassesInput()

        let bridge = GlassesMicBridge { [weak self] buffer in
            guard let self else { return }
            self.googleSTT.append(buffer)
            Task { @MainActor in
                self.trackSpeechEnergy(buffer)
            }
        }
        glassesMicBridge = bridge
        microphone.addListener(bridge)

        try await startGlassesMicrophone(
            microphone: microphone,
            owner: owner,
            context: owner == .passiveListen ? "passive listen" : "coach listen"
        )
        isListening = true
        startVADTimer()
        SoloChefLog.debug("stt: glasses mic started owner=\(owner)")
    }

    private func startGlassesMicrophone(
        microphone: Microphone,
        owner: GlassesMicOwner,
        context: String
    ) async throws {
        try await GlassesMicrophoneCoordinator.shared.start(
            microphone: microphone,
            owner: owner,
            context: context
        )
        glassesMicOwner = owner
    }

    private func prepareAudioSessionForGlassesInput() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            SoloChefLog.error("stt: audio session reset failed — \(error.localizedDescription)")
        }
    }

    private func logGlassesError(_ error: Error, context: String) {
        if let glassesError = error as? SolosGlassesError {
            SoloChefLog.error("stt: \(context) — \(String(reflecting: glassesError))")
        } else {
            SoloChefLog.error("stt: \(context) — \(String(reflecting: error))")
        }
    }

    private func evaluateBargeInEnergy(_ buffer: AVAudioPCMBuffer) {
        guard isBargeInMonitoring, !isListening else { return }

        let elapsed = Date.now.timeIntervalSince(bargeInMonitorStartedAt)
        guard elapsed >= SolosConfig.bargeInGracePeriodSeconds else { return }

        let rms = Self.rmsEnergy(of: buffer)
        if rms >= SolosConfig.bargeInEnergyThreshold {
            bargeInEnergeticBuffers += 1
            if bargeInEnergeticBuffers >= SolosConfig.bargeInConsecutiveBuffers {
                SoloChefLog.info("stt: barge-in detected rms=\(String(format: "%.4f", rms))")
                onBargeInDetected?()
            }
        } else {
            bargeInEnergeticBuffers = max(0, bargeInEnergeticBuffers - 1)
        }
    }

    private func releaseGlassesMicrophone() async {
        guard let microphone = glassesMicrophone else { return }
        if let owner = glassesMicOwner {
            await GlassesMicrophoneCoordinator.shared.release(
                microphone: microphone,
                owner: owner,
                context: "speech-input-release"
            )
            glassesMicOwner = nil
        } else if GlassesMicrophoneCoordinator.shared.sdkStarted {
            await GlassesMicrophoneCoordinator.shared.ensureStopped(
                microphone: microphone,
                context: "speech-input-force-release"
            )
        }
    }
    #endif

    // MARK: - Energy-based VAD

    private func trackSpeechEnergy(_ buffer: AVAudioPCMBuffer) {
        let rms = Self.rmsEnergy(of: buffer)
        if rms > speechEnergyThreshold {
            lastSpeechAt = .now
            if !hasCapturedSpeech {
                hasCapturedSpeech = true
                SoloChefLog.debug("stt: speech started rms=\(String(format: "%.4f", rms))")
            }
        }
    }

    private func startVADTimer() {
        vadSilenceTask?.cancel()

        vadSilenceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                guard let self, self.isListening else { return }

                // Safety max duration — avoid sending huge audio files
                let elapsed = Date.now.timeIntervalSince(self.listenStartedAt)
                if elapsed >= 30 {
                    SoloChefLog.debug("stt: vad max duration reached — finalising")
                    await self.finalizeAndSubmit()
                    return
                }

                guard self.hasCapturedSpeech else { continue }

                let silence = Date.now.timeIntervalSince(self.lastSpeechAt)
                if silence >= SolosConfig.vadSilenceTimeoutSeconds {
                    SoloChefLog.debug("stt: vad silence \(String(format: "%.1f", silence))s — finalising")
                    await self.finalizeAndSubmit()
                    return
                }
            }
        }
    }

    private func finalizeAndSubmit() async {
        guard isListening else { return }

        // IMPORTANT: nil out vadSilenceTask BEFORE calling finishListening.
        // finalizeAndSubmit() is called FROM inside vadSilenceTask — if we let
        // finishListening() call vadSilenceTask?.cancel() we self-cancel the running
        // task, which causes URLSession (Google STT) to throw CancellationError.
        vadSilenceTask = nil

        finishListening(submit: false)
        #if !targetEnvironment(simulator)
        await releaseGlassesMicrophone()
        #endif

        // Capture the buffer & language now — googleSTT.reset() clears them.
        let language = LanguageManager.shared.current

        // Run the network call in a detached task so it is immune to any
        // residual parent-task cancellation from the VAD timer chain.
        do {
            let text = try await Task.detached(priority: .userInitiated) { [googleSTT = self.googleSTT, language] in
                try await googleSTT.finalize(language: language)
            }.value
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                SoloChefLog.info("stt: final transcript=\(trimmed.prefix(120))")
                transcript = trimmed
                onFinalTranscript?(trimmed)
            } else {
                SoloChefLog.info("stt: empty transcript — nothing spoken or not recognised")
            }
        } catch {
            SoloChefLog.error("stt: Google STT finalize failed — \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Finish / cleanup

    private func releaseAudioCapture() async {
        finishListening(submit: false)
        #if !targetEnvironment(simulator)
        await releaseGlassesMicrophone()
        #endif
    }

    private func finishListening(submit: Bool) {
        vadSilenceTask?.cancel()
        vadSilenceTask = nil

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        #if !targetEnvironment(simulator)
        let shouldReleaseMic = glassesMicOwner != nil && !isBargeInMonitoring
        if let bridge = glassesMicBridge, !isBargeInMonitoring {
            glassesMicrophone?.removeListener(bridge)
            glassesMicBridge = nil
        }
        #endif

        isListening = false

        #if !targetEnvironment(simulator)
        if submit && shouldReleaseMic {
            Task { await releaseGlassesMicrophone() }
        }
        #endif
    }

    // MARK: - RMS helper

    private static func rmsEnergy(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count {
            let sample = channelData[i]
            sum += sample * sample
        }
        return sqrt(sum / Float(count))
    }
}

// MARK: - GlassesMicBridge

#if !targetEnvironment(simulator)
private final class GlassesMicBridge: MicrophoneListener {
    private let onBuffer: (AVAudioPCMBuffer) -> Void

    init(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) {
        self.onBuffer = onBuffer
    }

    func onMicrophoneDataReceived(_ pcm: AVAudioPCMBuffer) {
        onBuffer(pcm)
    }
}
#endif

// MARK: - Errors

enum SpeechInputError: LocalizedError {
    case unavailable
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .unavailable: "Speech recognition is not available on this device."
        case .notAuthorized: "Allow microphone access in Settings."
        }
    }
}
