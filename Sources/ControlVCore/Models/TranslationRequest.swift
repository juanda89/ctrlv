import Foundation

public struct TranslationRequest: Sendable {
    public let text: String
    public let targetLanguage: SupportedLanguage
    public let tone: Tone
    public let customTonePrompt: String?

    public init(text: String, targetLanguage: SupportedLanguage, tone: Tone, customTonePrompt: String? = nil) {
        self.text = text
        self.targetLanguage = targetLanguage
        self.tone = tone
        self.customTonePrompt = customTonePrompt
    }
}
