import Foundation

public struct TranslationResponse: Sendable {
    public let translatedText: String
    public let originalText: String
    public let targetLanguage: SupportedLanguage
    public let tone: Tone

    public init(translatedText: String, originalText: String, targetLanguage: SupportedLanguage, tone: Tone) {
        self.translatedText = translatedText
        self.originalText = originalText
        self.targetLanguage = targetLanguage
        self.tone = tone
    }
}
