import AVFoundation
import Foundation

/// Google Cloud Speech-to-Text REST client (synchronous recognize endpoint).
///
/// Usage:
///   1. Call `reset(sampleRate:)` when starting a new listening session.
///   2. Pipe every `AVAudioPCMBuffer` from the mic through `append(_:)`.
///   3. When the VAD timer fires, call `finalize(language:)` to send buffered
///      audio to Google and get back the transcript.
final class GoogleSTTService {

    private static let endpoint = "https://speech.googleapis.com/v1/speech:recognize"

    // Accumulated LINEAR16 PCM bytes
    private var audioBuffer = Data()

    // Sample rate captured from the first buffer
    private var sampleRate: Double = 16000

    // MARK: - Session management

    func reset() {
        audioBuffer = Data()
        sampleRate = 16000
    }

    // MARK: - Audio buffering

    /// Append a float32 planar PCM buffer to the accumulator, converting to LINEAR16.
    func append(_ buffer: AVAudioPCMBuffer) {
        // Capture sample rate from first buffer received
        if audioBuffer.isEmpty {
            sampleRate = buffer.format.sampleRate
        }

        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        var linear16 = Data(count: frameCount * 2)
        linear16.withUnsafeMutableBytes { ptr in
            let int16Ptr = ptr.bindMemory(to: Int16.self)
            for i in 0..<frameCount {
                let sample = channelData[i]
                let clamped = max(-1.0, min(1.0, sample))
                int16Ptr[i] = Int16(clamped * Float(Int16.max))
            }
        }
        audioBuffer.append(linear16)
    }

    // MARK: - Transcription

    /// Send all buffered audio to Google STT and return the transcript.
    /// Returns an empty string if nothing was recognised. Clears the buffer.
    func finalize(language: SupportedLanguage) async throws -> String {
        let bytes = audioBuffer
        audioBuffer = Data()

        guard !bytes.isEmpty else { return "" }

        SoloChefLog.info("google-stt: sending \(bytes.count) bytes sampleRate=\(Int(sampleRate)) lang=\(language.rawValue)")

        let token = try await GCPAuthHelper.shared.bearerToken()

        var config: [String: Any] = [
            "encoding": "LINEAR16",
            "sampleRateHertz": Int(sampleRate),
            "enableAutomaticPunctuation": true,
            "model": "latest_long",
            "useEnhanced": true
        ]

        switch language {
        case .english:
            config["languageCode"] = "en-US"
        case .cantonese:
            // yue-Hant-HK = Cantonese (Traditional, Hong Kong)
            // alternativeLanguageCodes lets bilingual HK speakers mix in English words
            config["languageCode"] = "yue-Hant-HK"
            config["alternativeLanguageCodes"] = ["en-US"]
        }

        let body: [String: Any] = [
            "config": config,
            "audio": ["content": bytes.base64EncodedString()]
        ]

        var request = URLRequest(url: URL(string: Self.endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw GoogleSTTError.httpError(0, "No HTTP response")
        }

        let rawBody = String(data: data, encoding: .utf8) ?? ""

        guard (200...299).contains(http.statusCode) else {
            SoloChefLog.error("google-stt: HTTP \(http.statusCode) — \(rawBody.prefix(300))")
            throw GoogleSTTError.httpError(http.statusCode, rawBody)
        }

        // Parse the first result's top alternative
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let first = results.first,
              let alternatives = first["alternatives"] as? [[String: Any]],
              let transcript = alternatives.first?["transcript"] as? String,
              !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            SoloChefLog.info("google-stt: no speech recognised — responseBytes=\(data.count)")
            return ""
        }

        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        SoloChefLog.info("google-stt: ✓ transcript=\(trimmed.prefix(120))")
        return trimmed
    }
}

// MARK: - Error

enum GoogleSTTError: LocalizedError {
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .httpError(let code, let body):
            "Google STT HTTP \(code): \(body.prefix(200))"
        }
    }
}
