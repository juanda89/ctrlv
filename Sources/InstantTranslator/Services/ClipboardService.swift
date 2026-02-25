import AppKit

final class ClipboardService {
    private var savedContents: [NSPasteboard.PasteboardType: Data] = [:]

    /// Save current pasteboard contents and clear it.
    func saveAndClear() {
        let pasteboard = NSPasteboard.general
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
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Read text from the pasteboard.
    func readText() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    /// Restore previously saved pasteboard contents.
    func restoreSaved() {
        let pasteboard = NSPasteboard.general
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
