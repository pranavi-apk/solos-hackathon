import SwiftUI
import AVFoundation

@MainActor
@Observable
final class VoiceAgentController {
    enum Mode {
        case askChef
        case snapWithGlasses
    }

    enum AgentState {
        case idle
        case listening
        case thinking
        case speaking
        case takingPhoto
    }

    let mode: Mode
    var state: AgentState = .idle
    var transcript: String = ""
    var statusMessage: String = ""
    var errorMessage: String?

    private let model: AppViewModel
    private let speechInput = SpeechInputService()
    private let coach = CookingCoachService()
    private var hasStarted = false
    private var isActive = false
    private var hasTakenPhoto = false
    private var bargeInPending = false

    init(mode: Mode, model: AppViewModel) {
        self.mode = mode
        self.model = model
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        isActive = true
        model.voiceAgentMode = mode
        model.isVoiceAgentActive = true

#if !targetEnvironment(simulator)
        if let service = model.glasses as? SolosGlassesService {
            speechInput.attachGlassesMicrophone(service.microphone)
        }
#endif

        speechInput.onFinalTranscript = { [weak self] text in
            guard let self, self.isActive else { return }
            Task { @MainActor in
                await self.handleTranscript(text)
            }
        }

        speechInput.onBargeInDetected = { [weak self] in
            guard let self, self.isActive else { return }
            Task { @MainActor in
                self.handleBargeIn()
            }
        }

        // Greeting based on mode and existing session
        let isCantonese = LanguageManager.shared.current == .cantonese
        if let session = model.recipeSession {
            let msg = isCantonese
                ? "歡迎返嚟！你頭先煮緊 \(session.dishName)。等我哋繼續上次嘅進度啦。"
                : "Welcome back! You were cooking \(session.dishName). Let's continue where we left off."
            await speak(msg)
            await startListening()
        } else if mode == .askChef {
            let msg = isCantonese
                ? "你好！我係你嘅 SoloChef。你今日想煮咩呀？"
                : "Hi! I'm your SoloChef. What would you like to cook today?"
            await speak(msg)
            await startListening()
        } else {
            // snapWithGlasses mode: start listening silently
            await startListening()
        }
    }

    func stop() {
        isActive = false
        model.isVoiceAgentActive = false
        speechInput.stopListening()
        Task {
            await speechInput.stopBargeInMonitoring()
        }
        state = .idle
        statusMessage = ""
    }

    // MARK: - Listening

    private func startListening() async {
        guard isActive, state != .takingPhoto else { return }

        let authorized = await speechInput.requestAuthorization()
        guard authorized else {
            statusMessage = "Microphone permission required"
            errorMessage = "Please allow microphone access in Settings."
            return
        }

        do {
            try await speechInput.startListening(allowPhoneFallback: true, micOwner: .coachSTT)
            state = .listening
            transcript = ""
            statusMessage = "Listening..."
            SoloChefLog.info("voice-agent: listening started")
        } catch {
            SoloChefLog.error("voice-agent: listen failed — \(error)")
            statusMessage = "Listen failed"
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Barge-in

    private func handleBargeIn() {
        guard state == .speaking else { return }
        SoloChefLog.info("voice-agent: barge-in detected — stopping TTS, will listen for user")
        bargeInPending = true
        SpeechService.shared.stopSpeaking()
        model.handleBargeIn()
        // Don't set state here — speak() will check bargeInPending when it returns
        // and transition correctly to .listening without losing context
    }

    // MARK: - Transcript handling

    private func handleTranscript(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isActive else { return }

        transcript = trimmed

        // If the user speaks while agent is speaking, the energy-based barge-in monitor
        // fires onBargeInDetected → handleBargeIn() which sets bargeInPending.
        // speak() will then call startListening() once TTS stops, so the user can
        // speak again. Any transcript arriving while still in .speaking state is
        // safely dropped here — it was the energy burst that triggered barge-in detection.
        guard state == .listening else { return }

        state = .thinking
        statusMessage = "Thinking..."
        SoloChefLog.info("voice-agent: transcript=\"\(trimmed.prefix(120))\"")

        await speechInput.stopBargeInMonitoring()

        // Reset hasTakenPhoto if the session was cleared (new dish started)
        if model.recipeSession == nil && hasTakenPhoto {
            hasTakenPhoto = false
            SoloChefLog.info("voice-agent: new dish detected — resetting photo state")
        }

        if mode == .snapWithGlasses && !hasTakenPhoto {
            await handleSnapFlow(transcript: trimmed)
        } else {
            await handleConversation(transcript: trimmed)
        }
    }

    // MARK: - Snap with Glasses flow

    private func handleSnapFlow(transcript: String) async {
        // If the user says any variation of "hey solos show me how to make this" or semantic equivalents:
        let intent = VoiceIntentDetector.detectIntent(in: transcript, appInForeground: true)
        if intent == .identifyAndCoach || intent == .takePhoto || intent == .tellRecipe {
            await takePhotoAndIdentify()
        } else {
            // Semantic matching or general talking triggers photo taking in snap mode:
            await takePhotoAndIdentify()
        }
    }

    private func takePhotoAndIdentify() async {
        state = .takingPhoto
        statusMessage = "Taking photo..."
        SoloChefLog.info("voice-agent: taking photo")

        let isCantonese = LanguageManager.shared.current == .cantonese
        // Spoken acknowledgment
        let waitMsg = isCantonese
            ? "請稍等，我影張相先。"
            : "Please wait a moment while I take a photo."
        await speak(waitMsg)

        // Trigger photo capture
        await model.snapDishAndGenerateRecipe()
        hasTakenPhoto = true

        if let session = model.recipeSession {
            // Already identified and started conversation
            // Speak the initial coach response that has been set in session messages by model.snapDishAndGenerateRecipe()
            if let lastMsg = session.messages.last, lastMsg.role == .assistant {
                let identifiedMsg = isCantonese
                    ? "我識別到呢道菜係 \(session.dishName)。\(lastMsg.content)"
                    : "I have identified this dish to be \(session.dishName). \(lastMsg.content)"
                await speak(identifiedMsg)
            }
            state = .idle
            await startListening()
        } else {
            let failMsg = isCantonese
                ? "我識別唔到呢道菜。你可以用眼鏡再望多次嗎？"
                : "I couldn't identify the dish. Could you try pointing your glasses at it again?"
            await speak(failMsg)
            state = .idle
            await startListening()
        }
    }

    // MARK: - Conversation flow

    private func handleConversation(transcript: String) async {
        if model.recipeSession == nil {
            let intent = VoiceIntentDetector.detectIntent(in: transcript, appInForeground: true)
            if intent == .identifyAndCoach || intent == .takePhoto {
                await takePhotoAndIdentify()
                return
            }
        }

        if model.recipeSession == nil && mode == .askChef {
            // User named a dish directly — set up session
            await model.askDishByName(transcript)
            if let session = model.recipeSession {
                if let lastMsg = session.messages.last, lastMsg.role == .assistant {
                    await speak(lastMsg.content)
                }
                state = .idle
                await startListening()
            }
        } else if var session = model.recipeSession {
            // Normal LLM conversation
            isBusy(thinking: true)
            defer { isBusy(thinking: false) }

            do {
                let reply = try await coach.converse(session: &session, userMessage: transcript)
                model.recipeSession = session
                model.saveCurrentSession()

                let isCantonese = LanguageManager.shared.current == .cantonese
                if reply.wantsNewDish {
                    // User wants a new dish — reset session AND photo state for fresh start
                    model.startNewDish()
                    hasTakenPhoto = false
                    let wantsNewMsg = isCantonese
                        ? "\(reply.spokenText) 你想改煮啲咩呢？"
                        : "\(reply.spokenText) What would you like to cook instead?"
                    await speak(wantsNewMsg)
                    state = .idle
                    await startListening()
                    return
                }

                await speak(reply.spokenText)

                // If recipe is ready, speak the completion
                if session.phase == .recipeReady, !session.recipeText.isEmpty {
                    let completion = isCantonese
                        ? "恭喜晒！你已經完成咗食譜。我幫你儲存好喇。你想煮其他野嗎？"
                        : "Congratulations! You've completed the recipe. I've saved it for you. Would you like to cook something else?"
                    await speak(completion)
                }
            } catch {
                SoloChefLog.error("voice-agent: converse failed — \(error)")
                let isCantonese = LanguageManager.shared.current == .cantonese
                let errMsg = isCantonese
                    ? "對唔住，系統有啲問題。你可以再講一次嗎？"
                    : "Sorry, I hit a snag. Could you say that again?"
                await speak(errMsg)
            }
            state = .idle
            await startListening()
        } else {
            let isCantonese = LanguageManager.shared.current == .cantonese
            let unsureMsg = isCantonese
                ? "我唔太清楚點做。你可以再試一次嗎？"
                : "I'm not sure what to do. Could you try again?"
            await speak(unsureMsg)
            state = .idle
            await startListening()
        }
    }

    // MARK: - TTS

    private func speak(_ text: String) async {
        guard isActive else { return }
        state = .speaking
        bargeInPending = false
        statusMessage = "Speaking..."
        SoloChefLog.info("voice-agent: speaking=\"\(text.prefix(120))\"")

        // Start barge-in monitoring while speaking (glasses mic only)
        Task {
            await speechInput.startBargeInMonitoring()
        }

        await model.glasses.speak(text)

        await speechInput.stopBargeInMonitoring()

        if bargeInPending {
            // User spoke during TTS — transition to listening to capture their words
            SoloChefLog.info("voice-agent: barge-in was pending after speak — resuming listening")
            bargeInPending = false
            state = .listening
            await startListening()
        } else if isActive {
            state = .idle
            statusMessage = ""
        }
    }

    private func isBusy(thinking: Bool) {
        model.isBusy = thinking
        model.busyMessage = thinking ? "Chef is thinking..." : ""
        if thinking {
            state = .thinking
            statusMessage = "Thinking..."
        }
    }
}
