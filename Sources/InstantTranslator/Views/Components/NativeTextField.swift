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

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(frame: .zero)
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .default
        field.font = NSFont.systemFont(ofSize: 13)
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.stringValue = text
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.update(parent: self)
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder
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
