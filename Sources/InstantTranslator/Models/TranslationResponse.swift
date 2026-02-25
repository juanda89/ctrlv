import Foundation

struct TranslationResponse {
    let translatedText: String
    let originalText: String
    let targetLanguage: SupportedLanguage
    let tone: Tone
}
