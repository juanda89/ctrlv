import AppKit
import XCTest
@testable import InstantTranslator

/// Tests the clipboard-fallback capture polling against a private named
/// pasteboard, simulating apps (Google Docs) that fulfill Cmd+C
/// asynchronously via JavaScript instead of writing synchronously.
final class ClipboardServiceTests: XCTestCase {
    private var pasteboard: NSPasteboard!
    private var service: ClipboardService!

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard(name: NSPasteboard.Name("tests.clipboard.\(UUID().uuidString)"))
        service = ClipboardService(pasteboard: pasteboard)
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        pasteboard = nil
        service = nil
        super.tearDown()
    }

    func test_waitForCopiedText_returnsImmediately_whenTextAlreadyPresent() async {
        let baseline = service.changeCount
        pasteboard.clearContents()
        pasteboard.setString("hola mundo", forType: .string)

        let start = Date()
        let result = await service.waitForCopiedText(since: baseline, timeout: 1.0)

        XCTAssertEqual(result, "hola mundo")
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5, "Should return well before the timeout")
    }

    func test_waitForCopiedText_capturesLateWrite_thatAFixedDelayWouldMiss() async {
        let baseline = service.changeCount

        // Simulate Google Docs' async JS copy: payload lands at ~200ms,
        // past the old fixed 90ms window.
        let board = pasteboard!
        Task.detached {
            try? await Task.sleep(nanoseconds: 200_000_000)
            board.clearContents()
            board.setString("texto tardío", forType: .string)
        }

        let result = await service.waitForCopiedText(since: baseline, timeout: 1.0)

        XCTAssertEqual(result, "texto tardío")
    }

    func test_waitForCopiedText_skipsWhitespaceIntermediateWrite() async {
        let baseline = service.changeCount

        // Docs-style sequence: whitespace-only intermediate write, then the
        // real payload. The poll must not settle for the whitespace.
        let board = pasteboard!
        Task.detached {
            try? await Task.sleep(nanoseconds: 60_000_000)
            board.clearContents()
            board.setString("\n", forType: .string)
            try? await Task.sleep(nanoseconds: 150_000_000)
            board.clearContents()
            board.setString("contenido real", forType: .string)
        }

        let result = await service.waitForCopiedText(since: baseline, timeout: 1.0)

        XCTAssertEqual(result, "contenido real")
    }

    func test_waitForCopiedText_timesOut_returningLastSeenValue() async {
        pasteboard.clearContents()
        let baseline = service.changeCount

        let start = Date()
        let result = await service.waitForCopiedText(since: baseline, timeout: 0.2)

        XCTAssertNil(result, "Nothing was ever written after the baseline")
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 0.2)
    }

    func test_writeAndReadText_roundTrip() {
        service.writeText("ida y vuelta")
        XCTAssertEqual(service.readText(), "ida y vuelta")
    }
}
