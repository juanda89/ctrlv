import XCTest
@testable import InstantTranslator

final class TranslatorFlowTests: XCTestCase {

    func test_shouldUseProgressivePaste_returnsTrue_whenOpenAIAndAutoPasteAndTrusted() {
        XCTAssertTrue(
            TranslatorViewModel.shouldUseProgressivePaste(
                provider: .openAI,
                autoPaste: true,
                isTrusted: true
            )
        )
    }

    func test_shouldUseProgressivePaste_returnsFalse_whenProviderIsNotOpenAI() {
        XCTAssertFalse(
            TranslatorViewModel.shouldUseProgressivePaste(
                provider: .claude,
                autoPaste: true,
                isTrusted: true
            )
        )
    }

    func test_shouldUseProgressivePaste_returnsFalse_whenAutoPasteDisabled() {
        XCTAssertFalse(
            TranslatorViewModel.shouldUseProgressivePaste(
                provider: .openAI,
                autoPaste: false,
                isTrusted: true
            )
        )
    }

    func test_shouldUseProgressivePaste_returnsFalse_whenAccessibilityNotTrusted() {
        XCTAssertFalse(
            TranslatorViewModel.shouldUseProgressivePaste(
                provider: .openAI,
                autoPaste: true,
                isTrusted: false
            )
        )
    }
}
