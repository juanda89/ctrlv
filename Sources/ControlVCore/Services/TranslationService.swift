import Foundation

/// Protocol for LLM translation providers.
public protocol TranslationProvider {
    func translate(text: String, systemPrompt: String) async throws -> String
}

public protocol StreamingTranslationProvider {
    func translateStream(text: String, systemPrompt: String) -> AsyncThrowingStream<String, Error>
}

/// Abstraction layer that delegates to the active provider.
public final class TranslationService {
    private let provider: TranslationProvider

    public init(provider: TranslationProvider) {
        self.provider = provider
    }

    public func translate(_ request: TranslationRequest) async throws -> TranslationResponse {
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
