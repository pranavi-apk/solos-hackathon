import SwiftUI
import UIKit
#if !targetEnvironment(simulator)
@preconcurrency import SolosAirGoSDK
#endif

@MainActor
@Observable
final class AppViewModel {
    var glasses: GlassesService
    var isBusy = false
    var busyMessage = ""
    var isWifiConnecting = false
    var lastError: String?
    var wifiError: String?
    var wifiErrorCanRetry = false
    /// Cleared after GlassesWiFiCard resets the password field.
    var wifiNeedsFreshPassword = false
    var recipeSession: RecipeSession?
    var showRecipeResult = false
    var showCoachChat = false
    var isVoiceAgentActive = false
    var voiceAgentMode: VoiceAgentController.Mode = .askChef
    var shouldShowNewDishCapture = false
    var lastCapturedThumbnail: UIImage?
    var currentSavedDishId: UUID?
    var savedDishes: [SavedDishSession] = []
    /// After TTS finishes, CoachChatView should start microphone capture.
    var pendingAutoListen = false
    /// Set when identify flow already queued the first coach utterance (avoids double TTS on appear).
    var initialCoachSpeakScheduled = false
    var isSpeaking = false
    /// Prevents overlapping coach TTS sessions from racing auto-listen state.
    private(set) var coachSpeakInFlight = false
    /// True while passive home-screen voice command listener is active.
    var isHomeVoiceListening = false
    /// Set to true when the user explicitly taps "Enter Kitchen" — persists until disconnect.
    var didEnterKitchen = false

    private let coach = CookingCoachService()

    init() {
        #if targetEnvironment(simulator)
        glasses = UnavailableGlassesService()
        #else
        glasses = SolosGlassesService()
        #endif
        reloadSavedDishes()
    }

    func reloadSavedDishes() {
        savedDishes = KitchenStore.shared.loadAll()
    }

    var isGlassesWifiConnected: Bool {
        glasses.isWifiConnected
    }

    var connectedGlassesName: String? {
        if let name = glasses.deviceName, !name.isEmpty {
            return name
        }
        if let name = SolosConnectionManager.shared.connectedGlasses?.name, !name.isEmpty {
            return name
        }
        return nil
    }

    func connectGlasses() async {
        SoloChefLog.info("glasses: connectGlasses() called")
        lastError = nil

        if glasses.isConnected || SolosConnectionManager.shared.isConnected {
            SoloChefLog.info("glasses: already connected — skipping connect()")
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            SoloChefLog.info("glasses: attempting to connect...")
            try await glasses.connect()
            SoloChefLog.info("glasses: connection succeeded")
        } catch is CancellationError {
            SoloChefLog.info("glasses: connection cancelled")
        } catch {
            SoloChefLog.error("glasses: connection failed - \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    func connectGlassesViaScan() async {
        isBusy = true
        lastError = nil
        defer { isBusy = false }

        do {
            try await SolosConnectionManager.shared.connectViaScan()
        } catch is CancellationError {
        } catch {
            lastError = error.localizedDescription
        }
    }

    func connectGlassesToHomeWiFi(
        ssid: String,
        password: String,
        monitor: GlassesWiFiMonitor
    ) async {
        guard !isWifiConnecting else {
            SoloChefLog.info("wifi: connect ignored — already in progress")
            return
        }

        wifiError = nil
        wifiErrorCanRetry = false
        wifiNeedsFreshPassword = false
        isWifiConnecting = true
        isBusy = true
        busyMessage = "Connecting glasses to Wi-Fi…"
        defer {
            isWifiConnecting = false
            isBusy = false
            busyMessage = ""
        }

        let trimmedSSID = ssid.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSSID.isEmpty, !trimmedPassword.isEmpty else {
            wifiError = "Enter both Wi-Fi name and password."
            return
        }

        let connection = SolosConnectionManager.shared
        if !connection.isConnected && !glasses.isConnected {
            SoloChefLog.info("wifi: bluetooth not connected — attempting auto-connect first")
            await connectGlasses()
        }

        guard connection.isConnected || glasses.isConnected else {
            wifiError = GlassesWiFiConnectError.bluetoothNotConnected.localizedDescription
            return
        }

        do {
            try await GlassesWiFiConnect.connectHomeNetwork(
                glasses: connection.connectedGlasses,
                ssid: trimmedSSID,
                password: trimmedPassword,
                monitor: monitor
            )
            wifiError = nil
            wifiErrorCanRetry = false
            wifiNeedsFreshPassword = false
        } catch is CancellationError {
            SoloChefLog.info("wifi: connect cancelled")
        } catch GlassesWiFiConnectError.alreadyConnecting {
            SoloChefLog.info("wifi: connect skipped — coordinator reports in progress")
        } catch {
            let mappedError: Error
            let diagnostics: WiFiConnectDiagnostics?
            if let failure = error as? GlassesWiFiConnect.WiFiConnectFailure {
                mappedError = failure.underlying
                diagnostics = failure.diagnostics
            } else {
                mappedError = error
                diagnostics = nil
            }
            wifiError = WiFiConnectionErrorMapper.userMessage(
                for: mappedError,
                ssid: ssid,
                diagnostics: diagnostics
            )
            wifiErrorCanRetry = WiFiConnectionErrorMapper.isConnectionTimeout(mappedError)
            wifiNeedsFreshPassword = WiFiConnectionErrorMapper.isPasswordIncorrect(mappedError)
        }
    }

    func disconnectGlasses() {
        glasses.disconnect()
    }

    func snapDishAndGenerateRecipe() async {
        guard GeminiAPIHelper.isAvailable else {
            lastError = CookingCoachError.missingAPIKey.localizedDescription
            SoloChefLog.error("flow: snap aborted — Gemini credentials missing")
            return
        }

        guard glasses.isConnected else {
            lastError = GlassesServiceError.notConnected.localizedDescription
            SoloChefLog.error("flow: glasses snap aborted — not connected")
            return
        }

        guard isGlassesWifiConnected else {
            lastError = GlassesServiceError.wifiRequiredForPhoto.localizedDescription
            wifiError = wifiError ?? SolosConfig.v2PhotoRequiresWiFiHint
            SoloChefLog.error("flow: glasses snap aborted — Wi-Fi not connected")
            return
        }

        isBusy = true
        busyMessage = "Taking photo with glasses…"
        lastError = nil
        defer { isBusy = false }

        SoloChefLog.info("flow: glasses snap started ble=\(glasses.isConnected) wifi=\(glasses.isWifiConnected)")

        // Pre-warm: let the glasses camera settle before capture
        try? await Task.sleep(for: .seconds(1))

        do {
            let image = try await captureGlassesPhotoWithRetry()
            SoloChefLog.info("flow: glasses photo OK \(Int(image.size.width))x\(Int(image.size.height))")
            lastCapturedThumbnail = image
            try await identifyDishAndStartCoach(from: image, source: "glasses")
        } catch is CancellationError {
            SoloChefLog.info("flow: glasses snap cancelled")
        } catch {
            SoloChefLog.error("flow: glasses snap failed — \(error.localizedDescription)")
            lastError = GlassesPhotoErrorMapper.userMessage(for: error)
        }
    }

    private func captureGlassesPhotoWithRetry() async throws -> UIImage {
        do {
            return try await glasses.takePhoto()
        } catch {
            #if !targetEnvironment(simulator)
            if let cameraError = error as? SolosCameraError {
                switch cameraError {
                case .timeout:
                    SoloChefLog.info("flow: camera timeout — waiting 2s cooldown before retry")
                    try? await Task.sleep(for: .seconds(2))
                    return try await glasses.takePhoto()
                default:
                    break
                }
            }
            #endif
            throw error
        }
    }

    #if DEBUG
    /// Hidden debug path — not shown in main UX.
    func snapWithPhoneCameraAndGenerateRecipe() async {
        guard GeminiAPIHelper.isAvailable else {
            lastError = CookingCoachError.missingAPIKey.localizedDescription
            SoloChefLog.error("flow: phone camera aborted — Gemini credentials missing")
            return
        }

        isBusy = true
        busyMessage = "Opening phone camera…"
        lastError = nil
        defer { isBusy = false }

        SoloChefLog.info("flow: phone camera snap started")

        do {
            let image = try await CameraCaptureService.captureFromDeviceCamera()
            SoloChefLog.info("flow: phone photo OK \(Int(image.size.width))x\(Int(image.size.height))")
            busyMessage = "Identifying dish…"
            try await identifyDishAndStartCoach(from: image, source: "phone-camera")
        } catch is CancellationError {
            SoloChefLog.info("flow: phone camera cancelled")
        } catch CameraCaptureService.CaptureError.cancelled {
            SoloChefLog.info("flow: phone camera cancelled by user")
        } catch {
            SoloChefLog.error("flow: phone camera failed — \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }
    #endif

    func pickPhotoFromLibraryAndGenerateRecipe() async {
        guard GeminiAPIHelper.isAvailable else {
            lastError = CookingCoachError.missingAPIKey.localizedDescription
            SoloChefLog.error("flow: photo library aborted — Gemini credentials missing")
            return
        }

        isBusy = true
        busyMessage = "Opening photo library…"
        lastError = nil
        defer { isBusy = false }

        SoloChefLog.info("flow: photo library pick started")

        do {
            let image = try await CameraCaptureService.pickFromPhotoLibrary()
            SoloChefLog.info("flow: library photo OK \(Int(image.size.width))x\(Int(image.size.height))")
            busyMessage = "Identifying dish…"
            try await identifyDishAndStartCoach(from: image, source: "photo-library")
        } catch is CancellationError {
            SoloChefLog.info("flow: photo library cancelled")
        } catch CameraCaptureService.CaptureError.cancelled {
            SoloChefLog.info("flow: photo library cancelled by user")
        } catch {
            SoloChefLog.error("flow: photo library failed — \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    /// Voice-triggered snap flow: acknowledge → glasses photo → identify → coach with auto-listen.
    func handleVoiceSnapAndCoachCommand() async {
        guard glasses.isConnected else {
            lastError = GlassesServiceError.notConnected.localizedDescription
            return
        }

        let ack = isGlassesWifiConnected
            ? "Got it — working on it."
            : "Connect glasses Wi-Fi first, then try again."
        await glasses.speak(ack)
        guard isGlassesWifiConnected else {
            lastError = GlassesServiceError.wifiRequiredForPhoto.localizedDescription
            return
        }
        await snapDishAndGenerateRecipe()
    }

    /// Handle semantic voice commands from home, connect, or coach session.
    func handleVoiceCommand(_ transcript: String, appInForeground: Bool = false) async -> Bool {
        let intent = VoiceIntentDetector.detectIntent(in: transcript, appInForeground: appInForeground)
        switch intent {
        case .takePhoto:
            SoloChefLog.info("voice: intent=takePhoto transcript=\(transcript)")
            await handleVoiceSnapAndCoachCommand()
            return true
        case .identifyAndCoach:
            SoloChefLog.info("voice: intent=identifyAndCoach transcript=\(transcript)")
            await handleVoiceSnapAndCoachCommand()
            return true
        case .tellRecipe:
            SoloChefLog.info("voice: intent=tellRecipe transcript=\(transcript)")
            if let session = recipeSession {
                if session.phase == .confirming || session.phase == .questioning {
                    await sendCoachMessage("Yes, let's cook it")
                } else if session.phase == .gatheringIngredients || session.phase == .cookingSteps {
                    showCoachChat = true
                    if let prompt = session.phase == .gatheringIngredients
                        ? session.currentIngredientPrompt()
                        : session.currentStepPrompt() {
                        await speakCoachAndListen(prompt)
                    }
                } else if session.phase == .recipeReady {
                    showRecipeResult = true
                }
            }
            return true
        case .none:
            return false
        }
    }

    /// Text-only path: user names a dish directly — no photo needed.
    func askDishByName(_ dishName: String) async {
        let trimmed = dishName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isBusy = true
        busyMessage = "Preparing your chef…"
        lastError = nil
        defer { isBusy = false }

        SoloChefLog.info("flow: ask-by-name dish=\(trimmed)")

        var session = RecipeSession(
            dishName: trimmed,
            photoAnalysis: "User asked by name — no photo.",
            phase: .confirming,
            clarifyingQuestionsAsked: 0
        )
        let confirmation = session.confirmationPrompt
        session.messages.append(RecipeMessage(role: .assistant, content: confirmation))

        showRecipeResult = false
        isBusy = false
        recipeSession = session
        currentSavedDishId = UUID()
        saveCurrentSession()
        showCoachChat = true
        SoloChefLog.info("flow: coach chat opened (ask-by-name) dish=\(trimmed)")

        let intro = "Great choice! I'll walk you through making \(trimmed). \(confirmation)"
        initialCoachSpeakScheduled = true
        Task {
            await speakCoachAndListen(intro)
            initialCoachSpeakScheduled = false
        }
    }

    private func identifyDishAndStartCoach(from image: UIImage, source: String) async throws {
        busyMessage = "Identifying dish…"
        SoloChefLog.info("flow: identify starting source=\(source) image=\(Int(image.size.width))x\(Int(image.size.height))")

        let (dishName, analysis) = try await coach.identifyDish(from: image)
        SoloChefLog.info("flow: identify success source=\(source) dish=\(dishName)")

        var session = RecipeSession(
            dishName: dishName,
            photoAnalysis: analysis,
            phase: .confirming,
            clarifyingQuestionsAsked: 0
        )
        let confirmation = session.confirmationPrompt
        session.messages.append(RecipeMessage(role: .assistant, content: confirmation))

        showRecipeResult = false

        isBusy = false
        recipeSession = session
        currentSavedDishId = UUID()
        saveCurrentSession(thumbnail: image)
        showCoachChat = true
        SoloChefLog.info("flow: coach chat opened dish=\(dishName)")

        let identification = "I've identified this as \(dishName). \(confirmation)"
        if !isVoiceAgentActive {
            initialCoachSpeakScheduled = true
            Task {
                await speakCoachAndListen(identification)
                initialCoachSpeakScheduled = false
            }
        }
    }

    /// Speaks on phone speaker (→ Bluetooth glasses), beeps, then queues mic capture.
    func speakCoachAndListen(_ text: String, autoListenAfter: Bool = true) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !coachSpeakInFlight else {
            SoloChefLog.debug("tts: speak skipped — already in flight")
            return
        }

        coachSpeakInFlight = true
        isSpeaking = true
        defer {
            isSpeaking = false
            coachSpeakInFlight = false
        }

        await glasses.speak(trimmed)

        if SpeechService.shared.wasInterrupted {
            SoloChefLog.info("tts: skipping beep — interrupted by barge-in")
            if autoListenAfter { pendingAutoListen = true }
            return
        }

        await BeepService.playReadyToSpeakBeep()
        if autoListenAfter {
            pendingAutoListen = true
        }
    }

    /// Called when user speaks during TTS — stops playback and queues listening.
    func handleBargeIn() {
        guard isSpeaking || SpeechService.shared.isSpeaking else { return }
        SoloChefLog.info("flow: barge-in — stopping TTS")
        SpeechService.shared.stopSpeaking()
        isSpeaking = false
        pendingAutoListen = true
    }

    func sendCoachMessage(_ text: String) async {
        guard var session = recipeSession else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if await handleVoiceCommand(trimmed) {
            return
        }

        isBusy = true
        busyMessage = "Chef is thinking…"
        lastError = nil
        defer { isBusy = false }

        do {
            let reply = try await coach.converse(session: &session, userMessage: trimmed)
            recipeSession = session
            saveCurrentSession()

            if reply.wantsNewDish {
                await speakCoachAndListen(reply.spokenText)
                return
            }

            await speakCoachAndListen(reply.spokenText)

            if session.phase == .recipeReady, !session.recipeText.isEmpty {
                showRecipeResult = true
            }
        } catch {
            lastError = error.localizedDescription
            await speakCoachAndListen("Sorry, I hit a snag. Could you say that again?")
        }
    }

    func askFollowUp(_ question: String) async {
        guard var session = recipeSession else { return }

        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isBusy = true
        busyMessage = "Chef is thinking…"
        lastError = nil
        defer { isBusy = false }

        do {
            let answer = try await coach.askFollowUp(session: &session, question: trimmed)
            recipeSession = session
            saveCurrentSession()
            await speakCoachAndListen(answer)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func startNewDish() {
        saveCurrentSession()
        recipeSession = nil
        currentSavedDishId = nil
        lastCapturedThumbnail = nil
        showRecipeResult = false
        showCoachChat = false
        isBusy = false
        isSpeaking = false
        pendingAutoListen = false
        initialCoachSpeakScheduled = false
        coachSpeakInFlight = false
        busyMessage = ""
        lastError = nil
    }

    func resumeSavedDish(_ saved: SavedDishSession) {
        recipeSession = saved.recipeSession
        currentSavedDishId = saved.id
        lastCapturedThumbnail = KitchenStore.shared.loadThumbnail(for: saved)
        showRecipeResult = false
        isVoiceAgentActive = true
        lastError = nil
    }

    func saveCurrentSession(thumbnail: UIImage? = nil) {
        guard let session = recipeSession else { return }
        let dishId = currentSavedDishId ?? UUID()
        if currentSavedDishId == nil {
            currentSavedDishId = dishId
        }

        var thumbnailFilename: String?
        if let existingFilename = savedDishes.first(where: { $0.id == dishId })?.thumbnailFilename {
            thumbnailFilename = existingFilename
        }
        if let thumb = thumbnail ?? lastCapturedThumbnail {
            thumbnailFilename = KitchenStore.shared.saveThumbnail(thumb, for: dishId)
        }

        let existing = savedDishes.first(where: { $0.id == dishId })
        let saved = SavedDishSession(
            id: dishId,
            dishName: session.dishName,
            createdAt: existing?.createdAt ?? .now,
            updatedAt: .now,
            recipeSession: session,
            thumbnailFilename: thumbnailFilename
        )
        KitchenStore.shared.save(saved)
        reloadSavedDishes()
    }

    /// Clears stale busy/navigation state when returning to Kitchen.
    func resetKitchenState() {
        if !isBusy {
            busyMessage = ""
        }
        showRecipeResult = false
        showCoachChat = false
        saveCurrentSession()
        reloadSavedDishes()
    }
}
