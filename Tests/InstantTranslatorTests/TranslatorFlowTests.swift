import XCTest
@testable import InstantTranslator

final class TranslatorFlowTests: XCTestCase {

    func test_shouldUseProgressivePaste_returnsFalse_forHostedCloudProvider() {
        XCTAssertFalse(
            TranslatorViewModel.shouldUseProgressivePaste(
                provider: .ctrlVCloud,
                autoPaste: true,
                isTrusted: true
            )
        )
    }

    func test_shouldUseProgressivePaste_returnsFalse_whenAutoPasteDisabled() {
        XCTAssertFalse(
            TranslatorViewModel.shouldUseProgressivePaste(
                provider: .ctrlVCloud,
                autoPaste: false,
                isTrusted: true
            )
        )
    }

    func test_shouldUseProgressivePaste_returnsFalse_whenAccessibilityNotTrusted() {
        XCTAssertFalse(
            TranslatorViewModel.shouldUseProgressivePaste(
                provider: .ctrlVCloud,
                autoPaste: true,
                isTrusted: false
            )
        )
    }
}
