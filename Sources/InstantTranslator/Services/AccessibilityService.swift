import AppKit
import ApplicationServices
import os

private let log = Logger(subsystem: "com.instanttranslator.app", category: "accessibility")

final class AccessibilityService {

    static var isTrusted: Bool {
        let trusted = AXIsProcessTrusted()
        log.info("AXIsProcessTrusted() = \(trusted)")
        return trusted
    }

    /// Requests permission with the system prompt dialog.
    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Opens System Settings directly to the Accessibility privacy pane.
    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Resets the Accessibility TCC entry for this app's bundle ID via tccutil,
    /// then re-requests permission. Useful when rebuilds invalidate the old code signature.
    static func resetAndReRequest() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.instanttranslator.app"
        log.info("Resetting TCC Accessibility for \(bundleID)")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleID]
        try? process.run()
        process.waitUntilExit()
        log.info("tccutil exit code: \(process.terminationStatus)")
        // Small delay then re-request so the OS shows the prompt
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Self.requestPermission()
        }
    }

    /// Returns diagnostic info about the current process for debugging.
    static var diagnosticInfo: String {
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let bundlePath = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier
        let trusted = AXIsProcessTrusted()
        return "Bundle: \(bundleID)\nPath: \(bundlePath)\nPID: \(pid)\nTrusted: \(trusted)"
    }

    func getSelectedText() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            log.error("No frontmost application found")
            return nil
        }
        log.info("Frontmost app: \(app.localizedName ?? "unknown") (PID: \(app.processIdentifier))")

        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var focusedElement: AnyObject?
        let focusResult = AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard focusResult == .success, let element = focusedElement else {
            log.error("Could not get focused element. AXError: \(focusResult.rawValue)")
            return nil
        }

        var selectedText: AnyObject?
        let textResult = AXUIElementCopyAttributeValue(
            element as! AXUIElement,
            kAXSelectedTextAttribute as CFString,
            &selectedText
        )

        guard textResult == .success else {
            log.error("Could not get selected text. AXError: \(textResult.rawValue)")
            return nil
        }

        let text = selectedText as? String
        log.info("Got selected text: \(text?.prefix(50) ?? "<nil>")")
        return text
    }

    func replaceSelectedText(with newText: String) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var focusedElement: AnyObject?
        let focusResult = AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard focusResult == .success else {
            log.error("replaceSelectedText: failed to get focused element. AXError: \(focusResult.rawValue)")
            return false
        }

        guard let element = focusedElement else {
            log.error("replaceSelectedText: no focused element")
            return false
        }

        var isSettable = DarwinBoolean(false)
        let settableResult = AXUIElementIsAttributeSettable(
            element as! AXUIElement,
            kAXSelectedTextAttribute as CFString,
            &isSettable
        )
        if settableResult != .success {
            log.error("replaceSelectedText: failed settable check. AXError: \(settableResult.rawValue)")
            return false
        }
        if !isSettable.boolValue {
            log.warning("replaceSelectedText: kAXSelectedTextAttribute is not settable")
            return false
        }

        let result = AXUIElementSetAttributeValue(
            element as! AXUIElement,
            kAXSelectedTextAttribute as CFString,
            newText as CFTypeRef
        )

        let success = result == .success
        log.info("replaceSelectedText: \(success ? "OK" : "FAILED (AXError: \(result.rawValue))")")
        return success
    }

    func beginProgressiveInsertionSession() -> ProgressiveInsertionSession? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            log.error("beginProgressiveInsertionSession: no frontmost app")
            return nil
        }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var focusedElement: AnyObject?
        let focusResult = AXUIElementCopyAttributeValue(
            axApp,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        guard focusResult == .success, let focusedElement else {
            log.error("beginProgressiveInsertionSession: no focused element (\(focusResult.rawValue))")
            return nil
        }

        let element = focusedElement as! AXUIElement
        guard let selectedRange = Self.selectedTextRange(for: element) else {
            log.error("beginProgressiveInsertionSession: missing selected text range")
            return nil
        }

        return ProgressiveInsertionSession(
            element: element,
            appPID: app.processIdentifier,
            initialRange: selectedRange
        )
    }

    private static func selectedTextRange(for element: AXUIElement) -> CFRange? {
        var selectedRangeValue: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRangeValue
        )
        guard result == .success,
              let selectedRangeValue,
              CFGetTypeID(selectedRangeValue) == AXValueGetTypeID() else {
            return nil
        }

        let rangeValue = selectedRangeValue as! AXValue
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(rangeValue, .cfRange, &range) else {
            return nil
        }
        return range
    }
}

enum ProgressiveInsertionFailureReason: String {
    case axInitFailed = "ax_init_failed"
    case streamFailed = "stream_failed"
    case focusChanged = "focus_changed"
    case setRangeFailed = "set_range_failed"
    case setTextFailed = "set_text_failed"
}

struct ProgressiveInsertionState {
    private let anchorLocation: Int
    private(set) var insertedUTF16Length: Int

    init(initialRange: CFRange) {
        anchorLocation = initialRange.location
        insertedUTF16Length = initialRange.length
    }

    mutating func rangeForCurrentText() -> CFRange {
        CFRange(location: anchorLocation, length: insertedUTF16Length)
    }

    mutating func commit(text: String) {
        insertedUTF16Length = text.utf16.count
    }
}

final class ProgressiveInsertionSession {
    private let element: AXUIElement
    private let appPID: pid_t
    private var state: ProgressiveInsertionState

    init(element: AXUIElement, appPID: pid_t, initialRange: CFRange) {
        self.element = element
        self.appPID = appPID
        self.state = ProgressiveInsertionState(initialRange: initialRange)
    }

    func apply(text: String) -> ProgressiveInsertionFailureReason? {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == appPID else {
            return .focusChanged
        }

        var range = state.rangeForCurrentText()
        guard let rangeValue = AXValueCreate(.cfRange, &range) else {
            return .setRangeFailed
        }

        let rangeResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            rangeValue
        )
        guard rangeResult == .success else {
            return .setRangeFailed
        }

        let textResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        guard textResult == .success else {
            return .setTextFailed
        }

        state.commit(text: text)
        return nil
    }
}
