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
        AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        guard let element = focusedElement else {
            log.error("replaceSelectedText: no focused element")
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
}
