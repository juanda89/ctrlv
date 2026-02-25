import Foundation

struct TranslationRequest {
    let text: String
    let targetLanguage: SupportedLanguage
    let tone: Tone
    let customTonePrompt: String?

    init(text: String, targetLanguage: SupportedLanguage, tone: Tone, customTonePrompt: String? = nil) {
        self.text = text
        self.targetLanguage = targetLanguage
        self.tone = tone
        self.customTonePrompt = customTonePrompt
    }
}
