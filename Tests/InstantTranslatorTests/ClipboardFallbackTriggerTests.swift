import XCTest
@testable import InstantTranslator

/// Regression: Google Docs makes Chrome report a whitespace-only AX selection
/// ("\n"). That must trigger the clipboard fallback, not be treated as text.
final class ClipboardFallbackTriggerTests: XCTestCase {
    func test_needsClipboardFallback_isTrue_forNilEmptyAndWhitespace() {
        XCTAssertTrue(TranslatorViewModel.needsClipboardFallback(nil))
        XCTAssertTrue(TranslatorViewModel.needsClipboardFallback(""))
        XCTAssertTrue(TranslatorViewModel.needsClipboardFallback("\n"))
        XCTAssertTrue(TranslatorViewModel.needsClipboardFallback(" \n\t "))
    }

    func test_needsClipboardFallback_isFalse_forRealText() {
        XCTAssertFalse(TranslatorViewModel.needsClipboardFallback("hola"))
        XCTAssertFalse(TranslatorViewModel.needsClipboardFallback("  hola  \n"))
        XCTAssertFalse(TranslatorViewModel.needsClipboardFallback("https://docs.google.com/x"))
    }
}
