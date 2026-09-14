import AppKit

final class ClipboardService {
    private let pasteboard: NSPasteboard
    private var savedContents: [NSPasteboard.PasteboardType: Data] = [:]

    /// `pasteboard` is injectable so tests can use a private named pasteboard
    /// instead of mutating the user's real clipboard.
    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    /// Monotonic counter the system bumps on every pasteboard write.
    var changeCount: Int {
        pasteboard.changeCount
    }

    /// Save current pasteboard contents and clear it.
    func saveAndClear() {
        savedContents = [:]
        for item in pasteboard.pasteboardItems ?? [] {
            for type in item.types {
                if let data = item.data(forType: type) {
                    savedContents[type] = data
                }
            }
        }
        pasteboard.clearContents()
    }

    /// Simulate Cmd+C to copy selected text.
    func simulateCopy() {
        postKeyEvent(virtualKey: 0x08, flags: .maskCommand) // 'C' key
    }

    /// Simulate Cmd+V to paste.
    func simulatePaste() {
        postKeyEvent(virtualKey: 0x09, flags: .maskCommand) // 'V' key
    }

    /// Write text to the pasteboard.
    func writeText(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Read text from the pasteboard.
    func readText() -> String? {
        pasteboard.string(forType: .string)
    }

    /// Polls the pasteboard after a simulated Cmd+C until real (non-whitespace)
    /// text arrives, or the timeout expires.
    ///
    /// A fixed post-copy delay is not enough for apps that handle Cmd+C in
    /// JavaScript (Google Docs renders in a canvas and serializes the selection
    /// asynchronously): the real payload can land hundreds of milliseconds
    /// later, sometimes preceded by an intermediate empty/whitespace write.
    /// Polling `changeCount` returns as soon as usable text exists instead of
    /// racing a timer against the target app.
    ///
    /// - Parameter baselineChangeCount: `changeCount` captured after
    ///   `saveAndClear()` and before `simulateCopy()`.
    /// - Returns: The first non-whitespace string written after the baseline.
    ///   On timeout, returns whatever was last seen (possibly whitespace or
    ///   nil) so callers can log/guard on the true final state.
    func waitForCopiedText(
        since baselineChangeCount: Int,
        timeout: TimeInterval = 0.6,
        pollInterval: TimeInterval = 0.025
    ) async -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        var lastSeen: String?

        while Date() < deadline {
            if pasteboard.changeCount != baselineChangeCount {
                lastSeen = readText()
                if let text = lastSeen,
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return text
                }
            }
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
        return lastSeen
    }

    /// Restore previously saved pasteboard contents.
    func restoreSaved() {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        for (type, data) in savedContents {
            item.setData(data, forType: type)
        }
        pasteboard.writeObjects([item])
        savedContents = [:]
    }

    // MARK: - Private

    private func postKeyEvent(virtualKey: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false)
        keyDown?.flags = flags
        keyUp?.flags = flags
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
