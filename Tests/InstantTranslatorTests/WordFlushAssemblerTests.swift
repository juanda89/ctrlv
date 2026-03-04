import XCTest
@testable import InstantTranslator

final class WordFlushAssemblerTests: XCTestCase {

    func test_append_returnsFlushedText_whenChunkEndsWithWhitespace() {
        var assembler = WordFlushAssembler(forceFlushInterval: 10)
        let flushed = assembler.append("Hola ")
        XCTAssertEqual(flushed, "Hola ")
        XCTAssertEqual(assembler.fullText, "Hola ")
    }

    func test_append_returnsNil_whenChunkHasNoBoundaryAndIntervalNotReached() {
        var assembler = WordFlushAssembler(forceFlushInterval: 10)
        let base = Date()
        XCTAssertNil(assembler.append("progresivo", at: base))
        XCTAssertEqual(assembler.fullText, "progresivo")
    }

    func test_append_forceFlushesPendingText_whenIntervalIsReached() {
        var assembler = WordFlushAssembler(forceFlushInterval: 0.12)
        let base = Date()
        XCTAssertNil(assembler.append("palabra", at: base))
        let forced = assembler.append("X", at: base.addingTimeInterval(0.15))
        XCTAssertEqual(forced, "palabraX")
    }

    func test_forceFlush_returnsFullText_whenPendingExists() {
        var assembler = WordFlushAssembler()
        _ = assembler.append("Hola")
        let flushed = assembler.forceFlush()
        XCTAssertEqual(flushed, "Hola")
        XCTAssertEqual(assembler.fullText, "Hola")
    }

    func test_append_preservesUnicode_whenChunksSplitEmoji() {
        var assembler = WordFlushAssembler(forceFlushInterval: 10)
        XCTAssertNil(assembler.append("he"))
        XCTAssertNil(assembler.append("llo"))
        XCTAssertNil(assembler.append(" 👩‍💻"))
        let flushed = assembler.append(" mundo ")
        XCTAssertEqual(flushed, "hello 👩‍💻 mundo ")
    }
}
