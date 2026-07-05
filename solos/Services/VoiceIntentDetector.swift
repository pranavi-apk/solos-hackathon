import Foundation

/// Lightweight semantic voice-command detection from STT transcripts.
enum VoiceIntent: Equatable {
    case takePhoto
    case identifyAndCoach
    case tellRecipe
    case none
}

enum VoiceIntentDetector {

    // MARK: - Snap / identify patterns per language

    /// Patterns are matched against the lowercased, punctuation-stripped transcript.
    /// Each language has broad coverage so any natural phrasing triggers.
    private static let snapPatterns: [SupportedLanguage: [String]] = [
        .english: [
            "tell me how", "how do i make", "how do i cook", "how to make", "how to cook",
            "what is this", "what's this", "identify", "take a photo", "take photo",
            "snap", "help me cook", "recipe", "teach me", "show me how",
        ],
        .cantonese: [
            // Traditional Chinese Cantonese phrases
            "點做", "點煮", "點整", "教我煮", "教我做", "教我整",
            "食譜係咩", "食譜", "幫我煮", "幫我做",
            "呢個係咩", "影相", "識別", "點樣煮", "點樣做",
            "告訴我食譜", "學整", "學煮",
        ],
    ]

    private static let readinessPhrases = [
        "done", "ready", "finished", "complete", "got it", "all set",
        "i'm ready", "im ready", "i am ready",
        // Cantonese
        "好喇", "做好喇", "準備好", "完成", "好了",
    ]

    private static let readinessPromptIndicators = [
        "say when", "when you're ready", "when you are ready",
        "let me know when", "say done", "say ready",
        // Cantonese
        "準備好話我知", "話我知幾時好",
    ]

    private static let recipeContinuationPatterns = [
        "start cooking", "let's cook", "lets cook", "walk me through", "start the recipe",
        // Cantonese
        "開始煮", "開始做", "開始整",
    ]

    // MARK: - Detection

    static func detectIntent(in transcript: String, appInForeground: Bool = false) -> VoiceIntent {
        let normalized = normalize(transcript)
        guard !normalized.isEmpty else { return .none }

        let lang = LanguageManager.currentLanguageForDetection

        // Check snap patterns for current language
        if let patterns = snapPatterns[lang] {
            if patterns.contains(where: { normalized.contains($0) }) {
                SoloChefLog.info("voice: intent=identifyAndCoach lang=\(lang.displayName) transcript=\(transcript.prefix(60))")
                return .identifyAndCoach
            }
        }

        // Always also check English patterns (user might speak English regardless of setting)
        if lang != .english, let enPatterns = snapPatterns[.english] {
            if enPatterns.contains(where: { normalized.contains($0) }) {
                SoloChefLog.info("voice: intent=identifyAndCoach (en fallback) transcript=\(transcript.prefix(60))")
                return .identifyAndCoach
            }
        }

        if recipeContinuationPatterns.contains(where: { normalized.contains($0) }) {
            return .tellRecipe
        }

        return .none
    }

    static func isReadinessAfterPrompt(_ transcript: String, lastAssistantMessage: String) -> Bool {
        let normalized = normalize(transcript)
        guard !normalized.isEmpty else { return false }

        let lastNorm = normalize(lastAssistantMessage)
        guard readinessPromptIndicators.contains(where: { lastNorm.contains($0) }) else {
            return false
        }

        if readinessPhrases.contains(where: { matchesPhrase($0, in: normalized) }) { return true }
        return normalized.split(separator: " ").count <= 4
            && readinessPhrases.contains(where: { normalized.contains($0) })
    }

    static func isCompletionUtterance(_ transcript: String) -> Bool {
        isReadinessAfterPrompt(transcript, lastAssistantMessage: "say when you're ready")
    }

    static func isMissingIngredient(_ transcript: String) -> Bool {
        let normalized = normalize(transcript)
        let missingTerms = [
            "don't have", "dont have", "do not have", "missing", "out of", "no ",
            // Cantonese
            "冇", "唔有", "唔夠", "缺少",
        ]
        return missingTerms.contains(where: { normalized.contains($0) })
    }

    // MARK: - Helpers

    private static func matchesPhrase(_ phrase: String, in normalized: String) -> Bool {
        normalized == phrase
            || normalized.hasPrefix(phrase + " ")
            || normalized.hasSuffix(" " + phrase)
    }

    private static func normalize(_ text: String) -> String {
        // \p{L} = any Unicode letter, \p{N} = any Unicode number — preserves Devanagari, CJK etc.
        text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s']"#, with: "", options: .regularExpression)
    }
}
