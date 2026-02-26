import SwiftUI

struct ShortcutSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var settingsVM: SettingsViewModel
    let onShortcutChanged: () -> Void

    private let quickPickLetters = ["J", "K", "L", "V", "X", "C"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Shortcut")
                .font(.system(size: 18, weight: .bold))

            Text("Command + Shift stay fixed. Choose only the final letter.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text("Current")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                ShortcutBadge(keys: settingsVM.shortcutKeyCaps)
            }

            HStack(spacing: 10) {
                Button {
                    moveSelection(offset: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Text(settingsVM.selectedShortcutOption.letter)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(MenuTheme.blue.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(MenuTheme.blue.opacity(0.35), lineWidth: 1)
                    )
                    .foregroundStyle(MenuTheme.blue)

                Button {
                    moveSelection(offset: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Quick picks")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(quickPickLetters, id: \.self) { letter in
                        quickPickButton(letter: letter)
                    }
                }
            }

            HStack {
                Text("More letters")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Picker("", selection: selectedKeyCodeBinding) {
                    ForEach(settingsVM.shortcutOptions) { option in
                        Text(option.letter).tag(option.carbonKeyCode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 92)
            }

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(MenuTheme.blue)
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    private var selectedKeyCodeBinding: Binding<UInt32> {
        Binding(
            get: { settingsVM.selectedShortcutOption.carbonKeyCode },
            set: { newValue in
                let option = ShortcutConfiguration.option(for: newValue)
                apply(option)
            }
        )
    }

    private func quickPickButton(letter: String) -> some View {
        let option = ShortcutConfiguration.option(forLetter: letter)
        let isSelected = option.carbonKeyCode == settingsVM.selectedShortcutOption.carbonKeyCode

        return Button {
            apply(option)
        } label: {
            Text(letter)
                .font(.system(size: 12, weight: isSelected ? .bold : .semibold))
                .frame(width: 34, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? MenuTheme.blue.opacity(0.16) : Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSelected ? MenuTheme.blue.opacity(0.45) : Color.primary.opacity(0.1), lineWidth: 1)
                )
                .foregroundStyle(isSelected ? MenuTheme.blue : .primary)
        }
        .buttonStyle(.plain)
    }

    private func moveSelection(offset: Int) {
        let options = settingsVM.shortcutOptions
        guard let currentIndex = options.firstIndex(where: {
            $0.carbonKeyCode == settingsVM.selectedShortcutOption.carbonKeyCode
        }) else { return }

        let nextIndex = (currentIndex + offset + options.count) % options.count
        apply(options[nextIndex])
    }

    private func apply(_ option: ShortcutKeyOption) {
        settingsVM.setShortcut(option)
        onShortcutChanged()
    }
}
