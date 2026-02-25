import Foundation

struct PromptBuilder {

    static func buildSystemPrompt(targetLanguage: String, tone: Tone, customTonePrompt: String? = nil) -> String {
        """
        You are a professional translator. Your task is to translate the user's text \
        into \(targetLanguage).

        Rules:
        - Return ONLY the translated text. No explanations, no notes, no quotes.
        - Preserve the original formatting (line breaks, punctuation style).
        - If the source text is already in \(targetLanguage), improve its grammar \
        and clarity instead of translating.
        \(toneInstruction(for: tone, customTonePrompt: customTonePrompt))
        """
    }

    private static func toneInstruction(for tone: Tone, customTonePrompt: String?) -> String {
        switch tone {
        case .original:
            return "- Maintain the original tone and register of the text."
        case .formal:
            return "- Use a professional, formal register. Suitable for business emails and official documents."
        case .casual:
            return "- Use a relaxed, conversational register. Suitable for chat messages and informal communication."
        case .concise:
            return "- Make the translation as brief as possible without losing meaning. Remove filler words and redundancy."
        case .custom:
            let cleaned = customTonePrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if cleaned.isEmpty {
                return "- Use a custom style chosen by the user while preserving meaning and accuracy."
            }
            return """
            - Apply the following custom style instruction from the user:
              \(cleaned)
            """
        }
    }
}
