import XCTest
@testable import InstantTranslator

final class TranslationServiceTests: XCTestCase {

    func test_translate_returnsResponse_whenProviderSucceeds() async throws {
        let mockProvider = MockProvider(result: "Hola mundo")
        let service = TranslationService(provider: mockProvider)
        let request = TranslationRequest(text: "Hello world", targetLanguage: .spanish, tone: .original)

        let response = try await service.translate(request)

        XCTAssertEqual(response.translatedText, "Hola mundo")
        XCTAssertEqual(response.originalText, "Hello world")
        XCTAssertEqual(response.targetLanguage, .spanish)
    }

    func test_translate_passesCorrectPromptToProvider() async throws {
        let mockProvider = MockProvider(result: "Bonjour")
        let service = TranslationService(provider: mockProvider)
        let request = TranslationRequest(text: "Hello", targetLanguage: .french, tone: .formal)

        _ = try await service.translate(request)

        XCTAssertTrue(mockProvider.lastSystemPrompt?.contains("French") ?? false)
        XCTAssertTrue(mockProvider.lastSystemPrompt?.contains("formal") ?? false)
    }
}

// MARK: - Mock

private final class MockProvider: TranslationProvider {
    let result: String
    var lastText: String?
    var lastSystemPrompt: String?

    init(result: String) {
        self.result = result
    }

    func translate(text: String, systemPrompt: String) async throws -> String {
        lastText = text
        lastSystemPrompt = systemPrompt
        return result
    }
}
