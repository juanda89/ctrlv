import Foundation

/// Protocol for LLM translation providers.
protocol TranslationProvider {
    func translate(text: String, systemPrompt: String) async throws -> String
}

/// Abstraction layer that delegates to the active provider.
final class TranslationService {
    private let provider: TranslationProvider

    init(provider: TranslationProvider) {
        self.provider = provider
    }

    func translate(_ request: TranslationRequest, apiKey: String) async throws -> TranslationResponse {
        guard !apiKey.isEmpty else {
            throw TranslationError.apiKeyMissing
        }

        let systemPrompt = PromptBuilder.buildSystemPrompt(
            targetLanguage: request.targetLanguage.rawValue,
            tone: request.tone,
            customTonePrompt: request.customTonePrompt
        )

        let translated = try await provider.translate(
            text: request.text,
            systemPrompt: systemPrompt
        )

        return TranslationResponse(
            translatedText: translated,
            originalText: request.text,
            targetLanguage: request.targetLanguage,
            tone: request.tone
        )
    }
}
