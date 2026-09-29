import XCTest
@testable import InstantTranslator

/// The field's own text decides whether an AX write really replaced the
/// selection (Slack's composer answers OK and keeps the old text).
final class ReplacementCheckTests: XCTestCase {
    private func check(_ field: String?, _ original: String, _ translated: String) -> TranslatorViewModel.ReplacementCheck {
        TranslatorViewModel.replacementCheck(fieldValue: field, original: original, translated: translated)
    }

    func test_replacementCheck_applied_whenFieldHasTranslation() {
        XCTAssertEqual(check("Hi team, can we meet on Thursday?", "Hola equipo, ¿nos vemos el jueves?", "can we meet on Thursday?"), .applied)
    }

    func test_replacementCheck_notApplied_whenFieldKeptOriginal() {
        let original = "let me know if you think there is metric you think I should add"
        let corrected = "let me know if you think there's a metric I should add"
        XCTAssertEqual(check("yeah\n\(original)\n", original, corrected), .notApplied)
    }

    func test_replacementCheck_ignoresWhitespaceReflow() {
        XCTAssertEqual(check("See you\n at the  office on Monday", "Nos vemos el lunes en la oficina", "See you at the office on Monday"), .applied)
    }

    func test_replacementCheck_notApplied_whenCorrectionOnlyDropsCharacters() {
        // "hello there!" is inside "hello there!!": the old text must win.
        XCTAssertEqual(check("hello there!!", "hello there!!", "hello there!"), .notApplied)
        XCTAssertEqual(check("hello there!", "hello there!!", "hello there!"), .applied)
    }

    func test_replacementCheck_applied_whenCorrectionOnlyAddsCharacters() {
        XCTAssertEqual(check("hello there.", "hello there", "hello there."), .applied)
        XCTAssertEqual(check("hello there", "hello there", "hello there."), .notApplied)
    }

    func test_replacementCheck_applied_whenNothingChanged() {
        XCTAssertEqual(check("same text", "same text", "same text"), .applied)
    }

    func test_replacementCheck_unknown_whenFieldUnreadableOrUnrelated() {
        XCTAssertEqual(check(nil, "hola", "hello"), .unknown)
        XCTAssertEqual(check("something else entirely", "hola", "hello"), .unknown)
    }
}
