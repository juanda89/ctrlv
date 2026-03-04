import XCTest
@testable import InstantTranslator

final class AccessibilityProgressiveSessionTests: XCTestCase {

    func test_rangeForCurrentText_returnsInitialSelection_whenSessionStarts() {
        var state = ProgressiveInsertionState(initialRange: CFRange(location: 12, length: 4))
        let range = state.rangeForCurrentText()
        XCTAssertEqual(range.location, 12)
        XCTAssertEqual(range.length, 4)
    }

    func test_commit_updatesUTF16Length_whenTextContainsEmoji() {
        var state = ProgressiveInsertionState(initialRange: CFRange(location: 0, length: 0))
        state.commit(text: "Hola 👩‍💻")
        XCTAssertEqual(state.insertedUTF16Length, "Hola 👩‍💻".utf16.count)
    }

    func test_rangeForCurrentText_usesUpdatedLength_afterCommit() {
        var state = ProgressiveInsertionState(initialRange: CFRange(location: 7, length: 2))
        state.commit(text: "palabra")
        let range = state.rangeForCurrentText()
        XCTAssertEqual(range.location, 7)
        XCTAssertEqual(range.length, "palabra".utf16.count)
    }
}
