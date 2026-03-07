import AppKit
import SwiftUI

enum APIKeyFieldValidationState: Equatable {
    case none
    case checking
    case valid(String)
    case invalid(String)
}

struct APIKeyField: View {
    let storedKey: String
    @Binding var draftKey: String
    let placeholder: String
    let isEditing: Bool
    let validationState: APIKeyFieldValidationState
    var showsStatus: Bool = true
    let onEdit: () -> Void
    let onCancel: () -> Void
    let onSave: () -> Void
    @State private var isKeyFieldFocused = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            NativeControlSurface(cornerRadius: 12, horizontalPadding: 10, verticalPadding: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "key.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MenuTheme.subtleText)

                    fieldBody
                        .frame(maxWidth: .infinity, alignment: .leading)

                    controls
                }
            }

            if showsStatus {
                HStack(spacing: 4) {
                    statusView
                }
            }
        }
        .onChange(of: isEditing, initial: true) { _, isNowEditing in
            if isNowEditing {
                DispatchQueue.main.async {
                    isKeyFieldFocused = true
                }
            } else {
                isKeyFieldFocused = false
            }
        }
    }

    @ViewBuilder
    private var fieldBody: some View {
        if isEditing {
            NativeSecureAPIKeyField(
                text: $draftKey,
                placeholder: placeholder,
                isFocused: $isKeyFieldFocused
            )
        } else {
            Text(readOnlyLabel)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(storedKey.isEmpty ? MenuTheme.tertiaryText : MenuTheme.subtleText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch validationState {
        case .none:
            if storedKey.isEmpty {
                Text("No key saved")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(MenuTheme.tertiaryText)
            } else {
                Text("Saved locally")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(MenuTheme.subtleText)
            }
        case .checking:
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.mini)
                Text("Verifying key...")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(MenuTheme.subtleText)
            }
        case .valid(let message):
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.green)
                Text(message)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.green)
            }
        case .invalid(let message):
            Text(message)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.red)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var controls: some View {
        if isEditing {
            NativeAccessoryButton(systemName: "xmark") {
                onCancel()
            }
            .accessibilityLabel("Cancel editing")

            NativeAccessoryButton(systemName: "checkmark", tint: MenuTheme.blue, filled: true) {
                onSave()
            }
            .accessibilityLabel("Save API key")
            .disabled(validationState == .checking)
        } else {
            NativeAccessoryButton(systemName: "square.and.pencil") {
                onEdit()
            }
            .accessibilityLabel("Edit API key")
        }
    }

    private var readOnlyLabel: String {
        if storedKey.isEmpty {
            return placeholder
        }
        return masked(storedKey)
    }

    private func masked(_ key: String) -> String {
        guard key.count > 8 else {
            return String(repeating: "•", count: max(4, key.count))
        }

        let prefix = key.prefix(4)
        let suffix = key.suffix(4)
        return "\(prefix)\(String(repeating: "•", count: 8))\(suffix)"
    }
}

private struct NativeSecureAPIKeyField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    @Binding var isFocused: Bool

    final class Coordinator: NSObject, NSTextFieldDelegate {
        private var parent: NativeSecureAPIKeyField

        init(parent: NativeSecureAPIKeyField) {
            self.parent = parent
        }

        func update(parent: NativeSecureAPIKeyField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSecureTextField else { return }
            parent.text = field.stringValue
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSSecureTextField {
        let field = NSSecureTextField(frame: .zero)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.stringValue = text
        field.lineBreakMode = .byTruncatingMiddle
        field.usesSingleLineMode = true
        return field
    }

    func updateNSView(_ nsView: NSSecureTextField, context: Context) {
        context.coordinator.update(parent: self)
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder
        }

        if isFocused {
            DispatchQueue.main.async {
                guard let window = nsView.window else { return }
                if window.firstResponder !== nsView.currentEditor() {
                    window.makeFirstResponder(nsView)
                }
            }
        }
    }
}
