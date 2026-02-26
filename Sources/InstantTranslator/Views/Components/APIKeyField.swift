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
    let onEdit: () -> Void
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "key.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                fieldBody
                    .frame(maxWidth: .infinity, alignment: .leading)

                controls
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )

            HStack(spacing: 4) {
                statusView
            }
        }
    }

    @ViewBuilder
    private var fieldBody: some View {
        if isEditing {
            SecureField(placeholder, text: $draftKey)
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .regular, design: .monospaced))
        } else {
            Text(readOnlyLabel)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(storedKey.isEmpty ? .tertiary : .secondary)
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
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            } else {
                Text("Saved locally")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        case .checking:
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.mini)
                Text("Verifying key...")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        case .valid(let message):
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
                Text(message)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
            }
        case .invalid(let message):
            Text(message)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.red)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var controls: some View {
        if isEditing {
            iconControlButton(
                systemName: "xmark",
                foreground: .secondary,
                background: Color.primary.opacity(0.08),
                accessibilityLabel: "Cancel editing"
            ) {
                onCancel()
            }

            iconControlButton(
                systemName: "checkmark",
                foreground: .white,
                background: MenuTheme.blue,
                accessibilityLabel: "Save API key"
            ) {
                onSave()
            }
            .disabled(validationState == .checking)
        } else {
            iconControlButton(
                systemName: "pencil",
                foreground: .secondary,
                background: Color.primary.opacity(0.08),
                accessibilityLabel: "Edit API key"
            ) {
                onEdit()
            }
        }
    }

    private var readOnlyLabel: String {
        if storedKey.isEmpty {
            return placeholder
        }
        return masked(storedKey)
    }

    private func iconControlButton(
        systemName: String,
        foreground: Color,
        background: Color,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(foreground)
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(background)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
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
