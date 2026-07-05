import Foundation

/// Mistral AI credentials — gitignored. Copy from Secrets.swift.example if missing.
enum Secrets {
    static let mistralAPIKey: String? = nil

    static var resolvedMistralAPIKey: String? {
        if let key = mistralAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            return key
        }
        if let env = ProcessInfo.processInfo.environment["MISTRAL_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !env.isEmpty {
            return env
        }
        return nil
    }
}
