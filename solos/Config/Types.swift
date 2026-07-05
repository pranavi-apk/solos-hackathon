import Foundation
import SwiftUI
import AVFoundation
import Observation
#if canImport(CoreBluetooth)
import CoreBluetooth
#endif

// SolosAirGoSDK integration: the xcframework at Vendor/SolosAirGoSDK.xcframework
// ships only an ios-arm64 (device) slice — no simulator slice. So we import the
// real SDK on device and use stub types on the simulator. The full public API is
// declared in the framework's .swiftinterface.
#if !targetEnvironment(simulator)
@preconcurrency import SolosAirGoSDK
#endif

// MARK: - SupportedLanguage
enum SupportedLanguage: String, CaseIterable, Identifiable {
    case english
    case cantonese
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .english: return "English"
        case .cantonese: return "廣東話"
        }
    }
    
    var flag: String {
        switch self {
        case .english: return "🇬🇧"
        case .cantonese: return "🇭🇰"
        }
    }
}

// MARK: - LanguageManager
@MainActor
@Observable
final class LanguageManager {
    static let shared = LanguageManager()
    
    var current: SupportedLanguage = .english
    
    static var currentLanguageForDetection: SupportedLanguage {
        shared.current
    }
}

// MARK: - SoloChefLog
enum SoloChefLog {
    nonisolated static func debug(_ message: String) {
        print("[DEBUG] \(message)")
    }
    
    nonisolated static func info(_ message: String) {
        print("[INFO] \(message)")
    }
    
    nonisolated static func warning(_ message: String) {
        print("[WARNING] \(message)")
    }
    
    nonisolated static func error(_ message: String) {
        print("[ERROR] \(message)")
    }
}

// MARK: - RecipeSession Phase
enum RecipePhase {
    case idle
    case confirming
    case questioning
    case gatheringIngredients
    case cookingSteps
    case recipeReady
}

// MARK: - RecipeMessage
struct RecipeMessage: Identifiable, Equatable {
    let id = UUID()
    let role: Role
    let content: String
    
    enum Role {
        case user
        case assistant
    }
}

// MARK: - RecipeSession
struct RecipeSession: Identifiable, Equatable {
    let id = UUID()
    let dishName: String
    let photoAnalysis: String
    var phase: RecipePhase
    var clarifyingQuestionsAsked: Int
    var messages: [RecipeMessage] = []
    var recipeText: String = ""
    
    var confirmationPrompt: String {
        "I've identified this as \(dishName). Would you like me to walk you through making it?"
    }
    
    func currentIngredientPrompt() -> String? {
        nil
    }
    
    func currentStepPrompt() -> String? {
        nil
    }
}

// MARK: - SavedDishSession
struct SavedDishSession: Identifiable, Equatable {
    let id: UUID
    let dishName: String
    let createdAt: Date
    let updatedAt: Date
    var recipeSession: RecipeSession
    var thumbnailFilename: String?
}

// MARK: - WiFiConnectDiagnostics
struct WiFiConnectDiagnostics: Equatable {
    let previousSSID: String?
    let previousStatus: String?
    let attempt: Int

    init(previousSSID: String?, previousStatus: String?, attempt: Int = 1) {
        self.previousSSID = previousSSID
        self.previousStatus = previousStatus
        self.attempt = attempt
    }
}

// MARK: - CookingCoachError
enum CookingCoachError: LocalizedError {
    case missingAPIKey
    case apiAccessDenied
    
    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Missing API credentials"
        case .apiAccessDenied: return "AI service access denied. Check that the Vertex AI or Generative Language API is enabled in your Google Cloud project."
        }
    }
}

// MARK: - GeminiAPIHelper
enum GeminiAPIHelper {
    static var isAvailable: Bool {
        GCPAuthHelper.isAvailable || Secrets.hasGeminiAPIKey
    }
}

// MARK: - KitchenStore
@MainActor
final class KitchenStore {
    static let shared = KitchenStore()
    
    func loadAll() -> [SavedDishSession] {
        []
    }
    
    func save(_ session: SavedDishSession) {
        
    }
    
    func delete(id: UUID) {
        
    }
    
    func saveThumbnail(_ image: UIImage, for id: UUID) -> String? {
        nil
    }
    
    func loadThumbnail(for session: SavedDishSession) -> UIImage? {
        nil
    }
}

// MARK: - GlassesService Protocol
protocol GlassesService {
    var isConnected: Bool { get }
    var deviceName: String? { get }
    var isCameraReady: Bool { get }
    var isWifiConnected: Bool { get }
    
    func connect() async throws
    func disconnect()
    func takePhoto() async throws -> UIImage
    func speak(_ text: String) async
}

// MARK: - UnavailableGlassesService
@MainActor
final class UnavailableGlassesService: GlassesService {
    var isConnected: Bool { false }
    var deviceName: String? { nil }
    var isCameraReady: Bool { false }
    var isWifiConnected: Bool { false }
    
    func connect() async throws {}
    func disconnect() {}
    func takePhoto() async throws -> UIImage {
        throw NSError(domain: "Glasses", code: 0, userInfo: [NSLocalizedDescriptionKey: "No glasses connected"])
    }
    func speak(_ text: String) async {
        await SpeechService.shared.speak(text)
    }
}

// MARK: - MockGlassesService
@MainActor
final class MockGlassesService: GlassesService {
    var isConnected: Bool { true }
    var deviceName: String? { "Solos Demo (Phone Speaker)" }
    var isCameraReady: Bool { true }
    var isWifiConnected: Bool { true }
    
    func connect() async throws {}
    func disconnect() {}
    
    func takePhoto() async throws -> UIImage {
        try await Task.sleep(for: .milliseconds(300))
        let size = CGSize(width: 400, height: 400)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
    
    func speak(_ text: String) async {
        await SpeechService.shared.speak(text)
    }
}

// MARK: - SpeechService
@MainActor
final class SpeechService {
    static let shared = SpeechService()
    
    var isSpeaking: Bool = false
    var wasInterrupted: Bool = false
    
    func speak(_ text: String) async {
        isSpeaking = true
        wasInterrupted = false
        // Simple placeholder - just wait a bit
        try? await Task.sleep(for: .milliseconds(500))
        isSpeaking = false
    }
    
    func stopSpeaking() {
        wasInterrupted = true
        isSpeaking = false
    }
}

// MARK: - BeepService
enum BeepService {
    static func playReadyToSpeakBeep() async {
        
    }
}

// MARK: - CookingCoachService
@MainActor
final class CookingCoachService {
    
    private func callGemini(contents: [[String: Any]], systemInstruction: String? = nil, jsonMode: Bool = false) async throws -> Data {
        var body: [String: Any] = [
            "contents": contents
        ]

        var generationConfig: [String: Any] = [
            "temperature": jsonMode ? 0.2 : 0.7,
            "topP": 0.95
        ]
        if jsonMode {
            generationConfig["responseMimeType"] = "application/json"
        }
        body["generationConfig"] = generationConfig

        if let systemInstruction = systemInstruction {
            body["systemInstruction"] = [
                "parts": [
                    ["text": systemInstruction]
                ]
            ]
        }

        let requestData = try JSONSerialization.data(withJSONObject: body)

        // Try Vertex AI service-account path first
        if GCPAuthHelper.isAvailable {
            let token = try await GCPAuthHelper.shared.bearerToken()
            let endpoint = "https://aiplatform.googleapis.com/v1/projects/still-algebra-501109-n0/locations/us/publishers/google/models/gemini-3.5-flash:generateContent"
            do {
                return try await executeGeminiRequest(endpoint: endpoint, headers: ["Authorization": "Bearer \(token)"], body: requestData)
            } catch let error as URLError where error.code.rawValue == 404 {
                SoloChefLog.info("gemini-api: Vertex AI 404, falling back to API key endpoint")
            } catch let error as URLError where error.code.rawValue == 403 {
                SoloChefLog.info("gemini-api: Vertex AI 403, falling back to API key endpoint")
            }
        }

        // Fallback to Generative Language API key endpoint
        if let key = Secrets.resolvedGeminiAPIKey {
            let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:generateContent?key=\(key)"
            do {
                return try await executeGeminiRequest(endpoint: endpoint, headers: [:], body: requestData)
            } catch let error as URLError where error.code.rawValue == 403 {
                SoloChefLog.error("gemini-api: API key 403 — blocked or invalid key")
                throw CookingCoachError.apiAccessDenied
            }
        }

        throw CookingCoachError.missingAPIKey
    }

    private func executeGeminiRequest(endpoint: String, headers: [String: String], body: Data) async throws -> Data {
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, val) in headers {
            request.setValue(val, forHTTPHeaderField: key)
        }
        request.httpBody = body
        request.timeoutInterval = 45

        SoloChefLog.info("gemini-api: sending request to endpoint=\(endpoint)")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        let rawBody = String(data: data, encoding: .utf8) ?? ""
        guard (200...299).contains(http.statusCode) else {
            SoloChefLog.error("gemini-api: HTTP \(http.statusCode) — \(rawBody.prefix(300))")
            throw URLError(.init(rawValue: http.statusCode))
        }

        return data
    }
    
    private func parseGeminiResponseText(from data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            let rawString = String(data: data, encoding: .utf8) ?? "no data"
            SoloChefLog.error("gemini-api: response parse failed — \(rawString.prefix(500))")
            throw URLError(.cannotParseResponse)
        }
        return text
    }
    
    private func cleanJSONString(_ raw: String) -> String {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            if let firstNewline = cleaned.firstIndex(of: "\n") {
                cleaned.removeSubrange(cleaned.startIndex...firstNewline)
            }
            if cleaned.hasSuffix("```") {
                cleaned.removeLast(3)
            }
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func identifyDish(from image: UIImage) async throws -> (String, String) {
        guard let jpegData = image.jpegData(compressionQuality: 0.7) else {
            throw GlassesServiceError.captureFailed
        }
        let base64Image = jpegData.base64EncodedString()
        
        let contents: [[String: Any]] = [
            [
                "role": "user",
                "parts": [
                    [
                        "inlineData": [
                            "mimeType": "image/jpeg",
                            "data": base64Image
                        ]
                    ],
                    [
                        "text": "Analyze this food image. Identify the dish shown. Return a JSON object with two fields:\n\"dishName\": a short, friendly name of the dish (e.g. \"Spaghetti Carbonara\", \"Chocolate Chip Cookies\").\n\"analysis\": a 1-2 sentence description of what you see (e.g. \"A beautifully plated pasta with creamy white sauce, topped with crispy bacon bits and fresh parsley.\").\n\nDo not include markdown blocks or any text outside of the raw JSON object."
                    ]
                ]
            ]
        ]
        
        let responseData = try await callGemini(contents: contents, jsonMode: true)
        let text = try parseGeminiResponseText(from: responseData)
        let cleanedJSON = cleanJSONString(text)
        
        guard let textData = cleanedJSON.data(using: .utf8),
              let responseDict = try? JSONSerialization.jsonObject(with: textData) as? [String: Any],
              let dishName = responseDict["dishName"] as? String,
              let analysis = responseDict["analysis"] as? String else {
            SoloChefLog.warning("gemini-api: failed to parse structured JSON from \(text)")
            return ("Delicious Dish", "I see some tasty food in front of you!")
        }
        
        return (dishName, analysis)
    }
    
    func converse(session: inout RecipeSession, userMessage: String) async throws -> (spokenText: String, wantsNewDish: Bool) {
        // 1. Append user message
        session.messages.append(RecipeMessage(role: .user, content: userMessage))
        
        // 2. Build instructions & history context
        let systemInstruction = """
        You are "SoloChef", a warm, enthusiastic, and highly professional AI Cooking Coach. The user is wearing smart glasses, so your spoken answers must be very concise (usually 1-3 sentences), friendly, and direct.

        We are cooking the dish: "\(session.dishName)".
        Our current session phase is: "\(session.phase)".
        Clarifying questions asked so far: \(session.clarifyingQuestionsAsked).

        Your goal is to guide the user from confirming the dish, to answering quick custom preferences, to gathering ingredients, to walking them through the steps one by one.

        ### Conversation flow:
        1. "confirming":
           - The user has been presented with the dish and asked if they want to cook it.
           - If they say yes or express interest, move to "questioning" (or "gatheringIngredients" if they are in a rush).
           - If they say no or want to cook something else, set "wantsNewDish" = true, suggest starting over, and keep phase as "confirming" or "idle".
        2. "questioning":
           - Ask 1 or 2 high-value questions to personalize the recipe (e.g. dietary restrictions, portion sizes, experience level).
           - Once they answer or if they want to skip, move to "gatheringIngredients".
        3. "gatheringIngredients":
           - Give them the list of ingredients needed. Speak a friendly summary (e.g. "You'll need tomatoes, garlic, olive oil, and spaghetti. Do you have these?").
           - If they have them, move to "cookingSteps".
        4. "cookingSteps":
           - Guide them step-by-step. Provide ONE step at a time, keeping it brief and easy to follow.
           - Wait for them to say "next", "ready", "done", or ask a question before giving the next step.
           - When all steps are completed, move to "recipeReady".
        5. "recipeReady":
           - The cooking is complete! Congratulate them.
           - You MUST generate the full detailed recipe in markdown and populate the "recipeText" field.

        ### Response format:
        You MUST respond with a JSON object containing these exact fields:
        - "spokenText": String (direct, concise, max 250 chars spoken to the user).
        - "phase": String (the next phase: "confirming", "questioning", "gatheringIngredients", "cookingSteps", "recipeReady").
        - "clarifyingQuestionsAsked": Integer (the updated count of clarifying questions asked so far).
        - "recipeText": String (the full detailed recipe in Markdown, including Title, Prep Time, Ingredients List, and Step-by-Step Instructions. ONLY generate/populate this when the phase is "recipeReady").
        - "wantsNewDish": Boolean (set to true if the user wants to cook something completely different).
        """
        
        var contents: [[String: Any]] = []
        contents.append([
            "role": "user",
            "parts": [
                ["text": "Context: We identified the dish as \"\(session.dishName)\" with analysis: \"\(session.photoAnalysis)\". This is our starting point."]
            ]
        ])
        contents.append([
            "role": "model",
            "parts": [
                ["text": "Understood. I will help the user make \(session.dishName). My first prompt is: \"\(session.confirmationPrompt)\""]
            ]
        ])
        
        for message in session.messages {
            let role = message.role == .user ? "user" : "model"
            contents.append([
                "role": role,
                "parts": [
                    ["text": message.content]
                ]
            ])
        }
        
        let responseData = try await callGemini(contents: contents, systemInstruction: systemInstruction, jsonMode: true)
        let text = try parseGeminiResponseText(from: responseData)
        let cleanedJSON = cleanJSONString(text)
        
        guard let textData = cleanedJSON.data(using: .utf8),
              let responseDict = try? JSONSerialization.jsonObject(with: textData) as? [String: Any],
              let spokenText = responseDict["spokenText"] as? String,
              let phaseString = responseDict["phase"] as? String,
              let questionsCount = responseDict["clarifyingQuestionsAsked"] as? Int,
              let wantsNewDish = responseDict["wantsNewDish"] as? Bool else {
            SoloChefLog.warning("gemini-api: failed to parse structured JSON from \(text)")
            let fallbackReply = "Okay, let's keep cooking!"
            session.messages.append(RecipeMessage(role: .assistant, content: fallbackReply))
            return (fallbackReply, false)
        }
        
        // 3. Update session properties
        session.clarifyingQuestionsAsked = questionsCount
        
        switch phaseString {
        case "confirming": session.phase = .confirming
        case "questioning": session.phase = .questioning
        case "gatheringIngredients": session.phase = .gatheringIngredients
        case "cookingSteps": session.phase = .cookingSteps
        case "recipeReady": session.phase = .recipeReady
        default: break
        }
        
        if let recipeText = responseDict["recipeText"] as? String, !recipeText.isEmpty {
            session.recipeText = recipeText
        }
        
        session.messages.append(RecipeMessage(role: .assistant, content: spokenText))
        return (spokenText, wantsNewDish)
    }
    
    func askFollowUp(session: inout RecipeSession, question: String) async throws -> String {
        session.messages.append(RecipeMessage(role: .user, content: question))
        
        var contents: [[String: Any]] = []
        contents.append([
            "role": "user",
            "parts": [
                ["text": "Context: We are cooking \"\(session.dishName)\" with the following recipe details:\n\(session.recipeText)\n\nPlease answer the user's question about this recipe or cooking in general. Keep the answer very concise (1-3 sentences) as it will be spoken to the user's smart glasses."]
            ]
        ])
        
        for message in session.messages {
            let role = message.role == .user ? "user" : "model"
            contents.append([
                "role": role,
                "parts": [
                    ["text": message.content]
                ]
            ])
        }
        
        let responseData = try await callGemini(contents: contents)
        let reply = try parseGeminiResponseText(from: responseData)
        
        session.messages.append(RecipeMessage(role: .assistant, content: reply))
        return reply
    }
}

// MARK: - CameraCaptureService
enum CameraCaptureService {
    enum CaptureError: Error {
        case cancelled
    }
    
    static func captureFromDeviceCamera() async throws -> UIImage {
        let size = CGSize(width: 400, height: 400)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
    
    static func pickFromPhotoLibrary() async throws -> UIImage {
        let size = CGSize(width: 400, height: 400)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.green.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - GlassesServiceError
enum GlassesServiceError: LocalizedError {
    case notConnected
    case cameraUnavailable
    case wifiRequiredForPhoto
    case sdkNotLinked
    case captureFailed

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Glasses not connected"
        case .cameraUnavailable: return "Camera not available"
        case .wifiRequiredForPhoto: return "Wi-Fi connection required for photo capture"
        case .sdkNotLinked: return "SolosAirGoSDK framework not linked - add it to enable real glasses connection"
        case .captureFailed: return "Failed to capture photo"
        }
    }
}

// MARK: - GlassesPhotoErrorMapper
enum GlassesPhotoErrorMapper {
    static func userMessage(for error: Error) -> String {
        let description = error.localizedDescription

        // 1. Specific SDK camera errors
        #if !targetEnvironment(simulator)
        if let cameraError = error as? SolosCameraError {
            switch cameraError {
            case .photoTakenButUnreachable:
                return GlassesServiceError.wifiRequiredForPhoto.localizedDescription
            case .timeout:
                return """
                The glasses camera timed out. Try again in a few seconds — \
                make sure the glasses are still connected and the hotspot is stable.
                """
            case .cameraBusy:
                return "Glasses camera is busy. Wait a moment and try again."
            default:
                let desc = cameraError.localizedDescription.lowercased()
                if desc.contains("stream") || desc.contains("network")
                    || desc.contains("no message available") {
                    return """
                    Photo download from glasses was interrupted. \
                    Make sure your iPhone hotspot is still on and the glasses are nearby, then try again.
                    """
                }
                return cameraError.localizedDescription
            }
        }
        #endif

        // 2. Wi-Fi not connected
        if let wifiError = error as? WiFiError, case .wifiNotConnected = wifiError {
            return GlassesServiceError.wifiRequiredForPhoto.localizedDescription
        }

        // 3. Heuristic: network / stream / unreachable keywords
        let lowered = description.lowercased()
        if lowered.contains("stream") || lowered.contains("network")
            || lowered.contains("wifi") || lowered.contains("wi-fi")
            || lowered.contains("unreachable") || lowered.contains("retrieve")
            || lowered.contains("no message available") {
            return GlassesServiceError.wifiRequiredForPhoto.localizedDescription
        }

        return description
    }

    static func isWifiPhotoFailure(_ error: Error) -> Bool {
        if let serviceError = error as? GlassesServiceError,
           case .wifiRequiredForPhoto = serviceError {
            return true
        }
        #if !targetEnvironment(simulator)
        if let cameraError = error as? SolosCameraError,
           case .photoTakenButUnreachable = cameraError {
            return true
        }
        if let wifiError = error as? WiFiError, case .wifiNotConnected = wifiError {
            return true
        }
        #endif
        let msg = userMessage(for: error)
        return msg == GlassesServiceError.wifiRequiredForPhoto.localizedDescription
    }
}

// MARK: - GlassesWiFiConnectError
enum GlassesWiFiConnectError: LocalizedError {
    case bluetoothNotConnected
    case alreadyConnecting
    
    var errorDescription: String? {
        switch self {
        case .bluetoothNotConnected: return "Bluetooth not connected"
        case .alreadyConnecting: return "Already connecting"
        }
    }
}

// MARK: - WiFiConnectionErrorMapper
enum WiFiConnectionErrorMapper {
    static func userMessage(for error: Error, ssid: String, diagnostics: WiFiConnectDiagnostics?) -> String {
        #if !targetEnvironment(simulator)
        if let wifiError = error as? WiFiError {
            switch wifiError {
            case .passwordIncorrect:
                return "Hotspot password looks incorrect. Double-check the password for \(ssid) and try again."
            case .connectionTimeout:
                return "Hotspot didn’t respond. Keep Personal Hotspot open on your iPhone and make sure Maximize Compatibility is turned on, then retry."
            case .glassesUnreachable:
                return "Glasses lost connection while joining \(ssid). Keep them nearby, leave Personal Hotspot on screen, then try again."
            case .wifiNotConnected:
                return "Glasses aren’t on Wi‑Fi yet. Stay on the hotspot screen and reconnect."
            case .fileNotFound:
                return "Hotspot setup failed — try toggling Personal Hotspot off and on, then reconnect."
            case .deleteFailed(let underlying, _):
                return "Hotspot connect hit an internal error: \(underlying.localizedDescription)"
            @unknown default:
                return error.localizedDescription
            }
        }
        #endif
        if let sdkError = error as? GlassesWiFiConnectError {
            switch sdkError {
            case .bluetoothNotConnected:
                return "Connect Bluetooth first, then join Wi‑Fi."
            case .alreadyConnecting:
                return "Glasses are already trying to join \(ssid). Give it a moment."
            }
        }
        if let description = diagnostics?.previousSSID, !description.isEmpty {
            return "Couldn’t switch from \(description) to \(ssid). Forget other Wi‑Fi networks on the glasses and retry."
        }
        return error.localizedDescription
    }
    
    static func isConnectionTimeout(_ error: Error) -> Bool {
        #if !targetEnvironment(simulator)
        if let wifiError = error as? WiFiError, case .connectionTimeout = wifiError {
            return true
        }
        #endif
        return false
    }
    
    static func isPasswordIncorrect(_ error: Error) -> Bool {
        #if !targetEnvironment(simulator)
        if let wifiError = error as? WiFiError, case .passwordIncorrect = wifiError {
            return true
        }
        #endif
        return false
    }
}

// MARK: - Simulator-only stubs
// On the simulator (no SDK slice available) we define lightweight stand-ins for
// the SDK types so the rest of the app compiles and previews. On device these are
// provided by `import SolosAirGoSDK` above.
#if targetEnvironment(simulator)

// MARK: - SolosGlassesError Stub
enum SolosGlassesError: Error {
    case unknown
}

// MARK: - Microphone Stub
@MainActor
final class Microphone {
    func addListener(_ listener: Any) {}
    func removeListener(_ listener: Any) {}
}

// MARK: - MicrophoneListener Stub
@MainActor
protocol MicrophoneListener: AnyObject {
    func onMicrophoneDataReceived(_ pcm: AVAudioPCMBuffer)
}

#endif // targetEnvironment(simulator)

// MARK: - GlassesMicOwner Stub
enum GlassesMicOwner {
    case coachSTT
    case bargeInMonitor
    case passiveListen
}

// MARK: - Connect timeout error
enum SolosConnectTimeoutError: LocalizedError {
    case timeout(targetSuffix: String, timeoutSeconds: TimeInterval)
    case unknown

    init(targetSuffix: String, timeoutSeconds: TimeInterval) {
        self = .timeout(targetSuffix: targetSuffix, timeoutSeconds: timeoutSeconds)
    }

    var errorDescription: String? {
        switch self {
        case .timeout(let targetSuffix, let timeoutSeconds):
            """
            Bluetooth connected scan timed out after \(Int(timeoutSeconds))s.
            Target model suffix: \(targetSuffix).
            Ensure:
            - glasses are powered on
            - iPhone Bluetooth is enabled
            - glasses are near
            - you’re not in a different room with another SoloChef unit using same suffix
            """
        case .unknown:
            "Bluetooth connection failed."
        }
    }
}

// MARK: - SolosGlassesService

#if targetEnvironment(simulator)
// Simulator: no SDK slice available — fail gracefully so previews build.
@MainActor
final class SolosGlassesService: GlassesService {
    var isConnected: Bool { false }
    var deviceName: String? { nil }
    var isCameraReady: Bool { false }
    var isWifiConnected: Bool { false }

    init() {
        SoloChefLog.info("glasses: SolosGlassesService initialized (simulator — SDK unavailable)")
    }

    func connect() async throws {
        SoloChefLog.warning("glasses: connect() not available in simulator")
        throw GlassesServiceError.sdkNotLinked
    }

    func disconnect() {}

    func takePhoto() async throws -> UIImage {
        throw GlassesServiceError.notConnected
    }

    func speak(_ text: String) async {
        await SpeechService.shared.speak(text)
    }
}
#else
// Device: real SolosAirGoSDK-backed service.
@MainActor
final class SolosGlassesService: GlassesService {
    private var sdkManager: Manager?
    private var sdkScanner: SolosAirGoSDK.Scanner?
    private(set) var glasses: SolosGlasses?

    var isConnected: Bool { glasses?.status == .connected }
    var deviceName: String? { glasses?.name }
    var isCameraReady: Bool { glasses?.camera != nil }
    var isWifiConnected: Bool { glasses?.wifi?.status == .connected }

    #if !targetEnvironment(simulator)
    /// Exposed so views can attach the glasses mic to SpeechInputService.
    var microphone: Microphone? { glasses?.audio?.microphone }
    #endif

    init() {
        SoloChefLog.info("glasses: SolosGlassesService initialized (SDK \(SolosSdkLibrary.getSdkVersion()))")
    }

    func connect() async throws {
        // If already connected, keep the existing session — don't disconnect + rescan.
        // Glasses that are already connected stop BLE advertising, so a fresh scan would time out.
        if let existing = glasses, existing.status == .connected {
            SoloChefLog.info("glasses: already connected to \(existing.name) — skipping scan")
            SolosConnectionManager.shared.publishConnected(existing)
            GlassesWiFiMonitor.shared.attach(to: existing)
            return
        }

        // Clean up any stale (disconnected) reference before scanning.
        if let existing = glasses {
            await existing.disconnect()
            glasses = nil
        }

        let manager = SolosAirGoSDK.Manager(brand: .solosAirGoV2)
        let scanner = manager.getScanner()
        sdkManager = manager
        sdkScanner = scanner

        let targetSuffix = SolosConfig.targetGlassesNameSuffix
        SoloChefLog.info("glasses: starting scan — target suffix \(targetSuffix)")

        // Use a retained delegate — Scanner.delegate is weak, so it must be held alive
        // for the duration of the scan by something strong (findFirst, below).
        let delegate = ConnectionScannerDelegate(targetSuffix: targetSuffix)
        scanner.delegate = delegate

        do {
            let found = try await delegate.findFirst(sdkScanner: scanner, timeout: SolosConfig.scanTimeoutSeconds)

            glasses = found
            // Share with SolosConnectionManager so the Wi-Fi flow can reach the same glasses.
            SolosConnectionManager.shared.publishConnected(found)
            // Start observing Wi-Fi status changes immediately.
            GlassesWiFiMonitor.shared.attach(to: found)

            SoloChefLog.info("glasses: found target — connecting to \(found.name)")
            try await found.connect()
            SoloChefLog.info("glasses: connected to \(found.name)")
            SolosConnectionManager.shared.publishConnected(found)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw error
        }
    }

    func disconnect() {
        guard let glasses else { return }
        SoloChefLog.info("glasses: disconnect()")
        Task { await glasses.disconnect() }
        self.glasses = nil
        SolosConnectionManager.shared.publishDisconnected()
    }

    func takePhoto() async throws -> UIImage {
        guard let glasses, isConnected else { throw GlassesServiceError.notConnected }
        guard let camera = glasses.camera else { throw GlassesServiceError.cameraUnavailable }

        let config = PhotoConfiguration.highQualityConfiguration(resolution: ._1280_960)
        let photo = try await camera.photo(with: config)
        guard let image = UIImage(data: photo.data) else {
            throw GlassesServiceError.captureFailed
        }
        return image
    }

    func speak(_ text: String) async {
        // Phone-speaker fallback for now; glasses TTS via PCM is a separate task.
        await SpeechService.shared.speak(text)
    }
}
#endif

#if targetEnvironment(simulator)
// MARK: - Simulator SDK stand-ins

@MainActor
final class SolosGlasses {
    let name: String
    let camera: SolosCamera
    let microphone: Microphone

    init(name: String) {
        self.name = name
        self.camera = SolosCamera()
        self.microphone = Microphone()
    }
}

@MainActor
final class SolosCamera {
    enum PhotoOptions {
        case `default`
    }

    func photo(with options: PhotoOptions) async throws -> UIImage {
        let size = CGSize(width: 400, height: 400)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}

enum SolosSdkLibrary {
    static func configure() {}
    static func getSdkVersion() -> String { "5.5.1-stub" }
}

@MainActor
final class BluetoothReadinessMonitor {
    static let shared = BluetoothReadinessMonitor()
    func warmUp() {}
}

@MainActor
@Observable
final class SolosConnectionManager {
    static let shared = SolosConnectionManager()

    var connectionPhase: ConnectionPhase = .idle
    var isConnected: Bool = false
    var connectedGlasses: SolosGlasses?
    var errorMessage: String?

    enum ConnectionPhase {
        case idle
        case scanning
        case connecting
        case connected
    }

    func connect() async throws {}
    func connectViaScan() async throws {}
    func disconnect() {}
    func preWarmScanner() {}
}

@MainActor
@Observable
final class GlassesWiFiMonitor {
    static let shared = GlassesWiFiMonitor()
    var isConnected: Bool = false
    func attach(to glasses: SolosGlasses?) {}
}

enum GlassesWiFiConnect {
    struct WiFiConnectFailure: Error {
        let underlying: Error
        let diagnostics: WiFiConnectDiagnostics?
    }

    static func connectHomeNetwork(glasses: SolosGlasses?, ssid: String, password: String, monitor: GlassesWiFiMonitor) async throws {}
}

@MainActor
final class GlassesMicrophoneCoordinator {
    static let shared = GlassesMicrophoneCoordinator()
    var sdkStarted: Bool = false
    var isPassiveListenActive: Bool = false
    func start(microphone: Microphone, owner: GlassesMicOwner, context: String) async throws {}
    func release(microphone: Microphone, owner: GlassesMicOwner, context: String) async {}
    func ensureStopped(microphone: Microphone, context: String) async {}
}

#else
// MARK: - Device SDK-backed connection + Wi-Fi plumbing

@MainActor
final class BluetoothReadinessMonitor {
    static let shared = BluetoothReadinessMonitor()

    /// No-op: the SDK Manager/Scanner power on CoreBluetooth lazily on first scan.
    func warmUp() {
        SoloChefLog.debug("ble: readiness warmUp (SDK powers CBCentralManager on scan)")
    }
}

@MainActor
@Observable
final class SolosConnectionManager {
    static let shared = SolosConnectionManager()

    private(set) var connectionPhase: ConnectionPhase = .idle
    private(set) var connectedGlasses: SolosGlasses?
    var errorMessage: String?

    enum ConnectionPhase {
        case idle
        case scanning
        case connecting
        case connected
    }

    var isConnected: Bool { connectedGlasses?.status == .connected }

    func connect() async throws {
        try await connectViaScan()
    }

    func connectViaScan() async throws {
        guard connectionPhase != .scanning && connectionPhase != .connecting else { return }
        connectionPhase = .scanning
        defer {
            if connectionPhase == .scanning { connectionPhase = .idle }
        }

        let manager = SolosAirGoSDK.Manager(brand: .solosAirGoV2)
        let scanner = manager.getScanner()
        let delegate = ConnectionScannerDelegate(targetSuffix: SolosConfig.targetGlassesNameSuffix)
        scanner.delegate = delegate

        do {
            let glasses = try await delegate.findFirst(sdkScanner: scanner, timeout: SolosConfig.scanTimeoutSeconds)
            connectionPhase = .connecting
            try await glasses.connect()
            connectedGlasses = glasses
            connectionPhase = .connected
            GlassesWiFiMonitor.shared.attach(to: glasses)
            SoloChefLog.info("connection: SolosConnectionManager connected \(glasses.name)")
        } catch {
            connectionPhase = .idle
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func disconnect() {
        guard let glasses = connectedGlasses else { return }
        Task { await glasses.disconnect() }
        connectedGlasses = nil
        connectionPhase = .idle
    }

    func preWarmScanner() {
        // SDK Manager/Scanner are created lazily during connect(); nothing to pre-warm here.
    }

    /// Called by SolosGlassesService when it has scanned + connected a glasses, so that
    /// the Wi-Fi flow (which reads `connectedGlasses` from here) can reach the same device.
    func publishConnected(_ glasses: SolosGlasses) {
        connectedGlasses = glasses
        connectionPhase = glasses.status == .connected ? .connected : .connecting
    }

    func publishDisconnected() {
        connectedGlasses = nil
        connectionPhase = .idle
    }
}

/// ScannerDelegate adapter that bridges the first matching result to async/await.
@MainActor
final class ConnectionScannerDelegate: ScannerDelegate {
    private let targetSuffix: String
    private var scanContinuation: CheckedContinuation<SolosGlasses, Error>?

    init(targetSuffix: String) {
        self.targetSuffix = targetSuffix
    }

    func findFirst(sdkScanner: SolosAirGoSDK.Scanner, timeout: TimeInterval) async throws -> SolosGlasses {
        // Set up the timeout BEFORE starting the scan, then start scanning once the
        // continuation is in place so a synchronous delegate callback isn't missed.
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<SolosGlasses, Error>) in
            self.scanContinuation = cont
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                if let cont = self.scanContinuation {
                    self.scanContinuation = nil
                    sdkScanner.stopScan()
                    cont.resume(throwing: SolosConnectTimeoutError(
                        targetSuffix: self.targetSuffix,
                        timeoutSeconds: timeout
                    ))
                }
            }
            sdkScanner.startScan()
        }
    }

    func scanner(_ sdkScanner: SolosAirGoSDK.Scanner, didFindGlasses foundGlasses: SolosGlasses) {
        // SolosConfig.matchesTargetDevice is @MainActor, so match inline to avoid actor hop.
        let name = foundGlasses.name
        let suffix = targetSuffix
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = normalized.hasSuffix(suffix) || normalized.localizedCaseInsensitiveContains(" \(suffix)")
        guard matches else { return }
        guard let cont = scanContinuation else { return }
        scanContinuation = nil
        sdkScanner.stopScan()
        cont.resume(returning: foundGlasses)
    }
}

@MainActor
@Observable
final class GlassesWiFiMonitor: WiFiComponentDelegate {
    static let shared = GlassesWiFiMonitor()

    private(set) var isConnected: Bool = false
    private(set) var connectedSSID: String?

    /// Observe the connected glasses' Wi-Fi status. Idempotent — safe to call on every connect.
    func attach(to glasses: SolosGlasses?) {
        // Detach from previous.
        NotificationCenter.default.removeObserver(self)

        guard let glasses, let wifi = glasses.wifi else {
            isConnected = false
            connectedSSID = nil
            return
        }
        wifi.delegate = self
        isConnected = wifi.status == .connected
        connectedSSID = wifi.ssid

        // Also listen to glasses-level status changes to refresh Wi-Fi state on reconnect.
        NotificationCenter.default.addObserver(
            forName: SolosGlasses.statusChangeNotification,
            object: glasses,
            queue: .main
        ) { notification in
            Task { @MainActor in
                // Re-read Wi-Fi status from the glasses' wifi component.
                if let status = glasses.wifi?.status {
                    self.isConnected = status == .connected
                    self.connectedSSID = glasses.wifi?.ssid
                } else {
                    self.isConnected = false
                    self.connectedSSID = nil
                }
            }
        }
    }

    nonisolated func wifi(_ wifiComponent: WiFiComponent, didBeginConnectingToSSID ssid: String) {
        Task { @MainActor in
            SoloChefLog.info("wifi: glasses began connecting to \(ssid)")
        }
    }

    nonisolated func wifi(_ wifiComponent: WiFiComponent, didFailToConnectToSSID ssid: String, withError error: any Error) {
        Task { @MainActor in
            SoloChefLog.error("wifi: glasses failed to connect to \(ssid) — \(error.localizedDescription)")
            isConnected = false
        }
    }

    nonisolated func wifi(_ wifiComponent: WiFiComponent, didConnectToSSID ssid: String) {
        Task { @MainActor in
            SoloChefLog.info("wifi: glasses connected to \(ssid)")
            isConnected = true
            connectedSSID = ssid
        }
    }

    nonisolated func wifi(_ wifiComponent: WiFiComponent, didDisconnectFromSSID ssid: String) {
        Task { @MainActor in
            SoloChefLog.info("wifi: glasses disconnected from \(ssid)")
            isConnected = false
            connectedSSID = nil
        }
    }
}

enum GlassesWiFiConnect {
    struct WiFiConnectFailure: Error {
        let underlying: Error
        let diagnostics: WiFiConnectDiagnostics?
    }

    /// Connect the glasses to a Wi-Fi network (e.g. iPhone Personal Hotspot).
    /// Throws `WiFiConnectFailure` so callers can map a precise user-facing message.
    static func connectHomeNetwork(
        glasses: SolosGlasses?,
        ssid: String,
        password: String,
        monitor: GlassesWiFiMonitor
    ) async throws {
        guard let glasses, let wifi = glasses.wifi else {
            throw WiFiConnectFailure(
                underlying: GlassesWiFiConnectError.bluetoothNotConnected,
                diagnostics: nil
            )
        }

        var diagnostics = WiFiConnectDiagnostics(
            previousSSID: wifi.ssid,
            previousStatus: String(describing: wifi.status)
        )

        // Attach monitor first so delegate callbacks update isConnected during connect.
        monitor.attach(to: glasses)

        if wifi.status == .connected {
            if wifi.ssid == ssid {
                SoloChefLog.info("wifi: already connected to \(ssid) — skipping reconnect request")
                return
            }
            SoloChefLog.info("wifi: disconnecting from \(wifi.ssid ?? "unknown") before joining \(ssid)")
            wifi.disconnect()
            do {
                try await wifi.disconnectAsync()
            } catch {
                SoloChefLog.warning("wifi: disconnectAsync threw — proceeding with reconnect anyway: \(error.localizedDescription)")
            }
            diagnostics = WiFiConnectDiagnostics(
                previousSSID: diagnostics.previousSSID,
                previousStatus: diagnostics.previousStatus,
                attempt: diagnostics.attempt + 1
            )
            try? await Task.sleep(for: .milliseconds(350))
        } else if wifi.status == .connecting {
            SoloChefLog.info("wifi: cancelling in-progress join before retrying \(ssid)")
            do {
                try await wifi.disconnectAsync()
            } catch {
                SoloChefLog.warning("wifi: disconnectAsync while cancelling join failed: \(error.localizedDescription)")
            }
            diagnostics = WiFiConnectDiagnostics(
                previousSSID: diagnostics.previousSSID,
                previousStatus: diagnostics.previousStatus,
                attempt: diagnostics.attempt + 1
            )
            try? await Task.sleep(for: .milliseconds(250))
        }

        monitor.attach(to: glasses)
        SoloChefLog.info("wifi: issuing connect to \(ssid) with allowOtherNetworks=true")
        do {
            try await wifi.connect(ssid: ssid, password: password, allowOtherNetworks: true)
        } catch let underlying as WiFiError {
            throw WiFiConnectFailure(underlying: underlying, diagnostics: diagnostics)
        } catch {
            throw WiFiConnectFailure(underlying: error, diagnostics: diagnostics)
        }
    }
}

// MARK: - GlassesMicrophoneCoordinator (device)
// Real glasses mic coordination lives in SpeechInputService. This coordinator is a
// thin bookkeeper that records who currently owns the glasses microphone so that
// the coach STT path and the passive-listen path don't fight over `Microphone.start()`.
@MainActor
final class GlassesMicrophoneCoordinator {
    static let shared = GlassesMicrophoneCoordinator()

    private(set) var sdkStarted: Bool = false
    private(set) var isPassiveListenActive: Bool = false
    private(set) var currentOwner: GlassesMicOwner?

    func start(microphone: Microphone, owner: GlassesMicOwner, context: String) async throws {
        SoloChefLog.info("mic: start owner=\(owner) context=\(context)")
        try await microphone.start()
        sdkStarted = true
        currentOwner = owner
        if owner == .passiveListen { isPassiveListenActive = true }
    }

    func release(microphone: Microphone, owner: GlassesMicOwner, context: String) async {
        SoloChefLog.info("mic: release owner=\(owner) context=\(context)")
        if currentOwner == owner {
            try? await microphone.stop()
            sdkStarted = false
            currentOwner = nil
        }
        if owner == .passiveListen { isPassiveListenActive = false }
    }

    func ensureStopped(microphone: Microphone, context: String) async {
        SoloChefLog.info("mic: ensureStopped context=\(context)")
        try? await microphone.stop()
        sdkStarted = false
        currentOwner = nil
        isPassiveListenActive = false
    }
}

#endif // targetEnvironment(simulator)
