import AppKit
import SwiftUI

/// SwiftUI wrapper for NSTextField that reliably accepts focus inside NSPopover.
struct NativeTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var keyboardType: KeyboardType = .text
    var maxLength: Int? = nil
    var autoFocus: Bool = false
    var onSubmit: (() -> Void)? = nil

    enum KeyboardType {
        case text
        case numeric
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        private var parent: NativeTextField
        var didApplyAutoFocus: Bool = false

        init(parent: NativeTextField) {
            self.parent = parent
        }

        func update(parent: NativeTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            var value = field.stringValue
            if case .numeric = parent.keyboardType {
                value = value.filter { $0.isNumber }
            }
            if let maxLength = parent.maxLength, value.count > maxLength {
                value = String(value.prefix(maxLength))
            }
            if value != field.stringValue {
                field.stringValue = value
            }
            parent.text = value
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit?()
                return true
            }
            return false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    /// Sets the placeholder with an explicit semantic color. `.placeholderTextColor`
    /// resolves against the field's current appearance at draw time, so with the
    /// appearance pinned in updateNSView it always has contrast on the field.
    private func applyPlaceholder(to field: NSTextField) {
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor.placeholderTextColor,
                .font: field.font ?? NSFont.systemFont(ofSize: 13),
            ]
        )
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(frame: .zero)
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .default
        field.font = NSFont.systemFont(ofSize: 13)
        // Explicit label color so typed text is always readable regardless of
        // the popover's (light/dark) background.
        field.textColor = .labelColor
        field.delegate = context.coordinator
        field.stringValue = text
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        applyPlaceholder(to: field)
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.update(parent: self)
        // Pin the field's appearance to its window's. Inside an NSPopover a
        // bridged NSTextField can otherwise keep a stale (light) appearance
        // while the popover renders dark, which made the placeholder render
        // dark-on-dark and effectively invisible.
        if let windowAppearance = nsView.window?.effectiveAppearance,
           nsView.appearance != windowAppearance {
            nsView.appearance = windowAppearance
        }
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if nsView.placeholderAttributedString?.string != placeholder {
            applyPlaceholder(to: nsView)
        }

        if autoFocus, !context.coordinator.didApplyAutoFocus {
            context.coordinator.didApplyAutoFocus = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                guard let window = nsView.window else { return }
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(nsView)
            }
        }
    }
}
