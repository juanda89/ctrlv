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

    /// Result of reading text from the focused UI element.
    struct CaptureResult {
        let text: String
        /// True if `text` came from kAXValueAttribute (whole field content
        /// because no selection existed). False if from kAXSelectedTextAttribute.
        let isWholeFieldValue: Bool
    }

    /// Reads the text the user wants translated.
    ///
    /// Priority:
    ///   1. kAXSelectedTextAttribute — the actual user selection (preferred)
    ///   2. kAXValueAttribute        — the entire field content, used when the
    ///      focused element is a text input and the user typed something but
    ///      hasn't selected it (e.g. Chrome URL bar with cursor at end).
    ///
    /// The second fallback is gated on "is this a text-input-like element?" so
    /// we don't accidentally translate giant body paragraphs of a webpage when
    /// the user really did mean to translate a (no-op) selection.
    func capture() -> CaptureResult? {
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

        let axElement = element as! AXUIElement

        // 1. Try selection first (preferred — preserves user intent)
        var selectedText: AnyObject?
        let textResult = AXUIElementCopyAttributeValue(
            axElement,
            kAXSelectedTextAttribute as CFString,
            &selectedText
        )

        if textResult == .success, let text = selectedText as? String, !text.isEmpty {
            log.info("Got selected text: \(text.prefix(50))")
            return CaptureResult(text: text, isWholeFieldValue: false)
        }

        // 2. Fallback: if the focused element is an input field and contains
        // typed content, read the whole value. This covers Chrome's URL bar,
        // single-line text inputs, and search fields when the user typed
        // something and pressed the shortcut without selecting.
        if Self.isTextInputElement(axElement) {
            var value: AnyObject?
            let valueResult = AXUIElementCopyAttributeValue(
                axElement,
                kAXValueAttribute as CFString,
                &value
            )
            if valueResult == .success, let text = value as? String, !text.isEmpty {
                log.info("No selection; using whole field value: \(text.prefix(50))")
                return CaptureResult(text: text, isWholeFieldValue: true)
            }
            log.info("Selection empty and value read returned nothing (AXError: \(valueResult.rawValue))")
        } else {
            log.info("Selection empty and focused element is not a text input")
        }

        log.error("Could not get any text from focused element")
        return nil
    }

    /// Back-compat wrapper that returns just the text. Loses the
    /// "isWholeFieldValue" signal — callers that need it should use capture().
    func getSelectedText() -> String? {
        capture()?.text
    }

    /// Returns true if the element is a text-input-like role where reading its
    /// full value as a translation source is desirable. Avoids reading whole
    /// document bodies on the web (those are typically AXWebArea / AXStaticText).
    private static func isTextInputElement(_ element: AXUIElement) -> Bool {
        var roleValue: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        guard result == .success, let role = roleValue as? String else {
            return false
        }
        switch role {
        case "AXTextField",          // Chrome omnibox, generic single-line input
             "AXSearchField",        // Safari/system search fields
             "AXComboBox",           // editable dropdowns
             "AXTextArea":           // multi-line input fields
            return true
        default:
            return false
        }
    }

    /// Replaces the user's selection with `newText`. If `replaceWholeValue` is
    /// true (used when the source was read via kAXValueAttribute because no
    /// selection existed), the entire field content is replaced instead.
    func replaceSelectedText(with newText: String, replaceWholeValue: Bool = false) -> Bool {
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

        let axElement = element as! AXUIElement
        let attribute = replaceWholeValue ? kAXValueAttribute : kAXSelectedTextAttribute

        var isSettable = DarwinBoolean(false)
        let settableResult = AXUIElementIsAttributeSettable(
            axElement,
            attribute as CFString,
            &isSettable
        )
        if settableResult != .success {
            log.error("replaceSelectedText: failed settable check on \(attribute). AXError: \(settableResult.rawValue)")
            return false
        }
        if !isSettable.boolValue {
            log.warning("replaceSelectedText: \(attribute) is not settable")
            return false
        }

        let result = AXUIElementSetAttributeValue(
            axElement,
            attribute as CFString,
            newText as CFTypeRef
        )

        let success = result == .success
        log.info("replaceSelectedText[\(attribute)]: \(success ? "OK" : "FAILED (AXError: \(result.rawValue))")")
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
