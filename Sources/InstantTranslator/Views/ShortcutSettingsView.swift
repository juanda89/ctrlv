import AppKit
import SwiftUI

struct ShortcutSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var settingsVM: SettingsViewModel

    /// The profile whose shortcut is being edited. Always explicit — a nil
    /// fallback here once caused edits aimed at profile 2 to silently land on
    /// profile 1 (stale sheet state), so the ambiguity is banned by design.
    let profileID: UUID

    let onShortcutChanged: () -> Void

    /// When presented inline (inside the popover, no sheet), the host passes
    /// a closure to exit the editor. When presented as a real sheet, leave nil
    /// and the environment dismiss is used.
    let onFinish: (() -> Void)?

    init(
        settingsVM: SettingsViewModel,
        profileID: UUID,
        onShortcutChanged: @escaping () -> Void,
        onFinish: (() -> Void)? = nil
    ) {
        self._settingsVM = Bindable(settingsVM)
        self.profileID = profileID
        self.onShortcutChanged = onShortcutChanged
        self.onFinish = onFinish
    }

    private let quickPickLetters = ["V", "J", "K", "L", "X", "C"]
    @State private var keyMonitor: Any?
    @State private var pendingOption: ShortcutKeyOption = ShortcutConfiguration.defaultOption
    @State private var collisionMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Shortcut")
                    .font(.system(size: 18, weight: .bold))

                Spacer()

                Button {
                    finish()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text("Command + Shift stay fixed. Press only one letter key now.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Current")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ShortcutBadge(keys: ["⌘", "⇧", pendingOption.letter])
                }

                HStack(spacing: 10) {
                    Text(pendingOption.letter)
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(MenuTheme.blue.opacity(0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(MenuTheme.blue.opacity(0.35), lineWidth: 1)
                        )
                        .foregroundStyle(MenuTheme.blue)
                }
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

            if let collisionMessage {
                Text(collisionMessage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.red)
            } else {
                Text("Tip: press a single letter. Invalid keys play the system warning sound.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Spacer()
                Button("Save") {
                    saveAndClose()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(MenuTheme.blue)
                .disabled(collisionMessage != nil)
            }
        }
        .padding(14)
        .frame(width: 320)
        .onAppear {
            pendingOption = currentOption
            updateCollisionMessage()
            startKeyCapture()
        }
        .onDisappear {
            stopKeyCapture()
        }
    }

    private var currentOption: ShortcutKeyOption {
        if let profile = settingsVM.settings.profiles.first(where: { $0.id == profileID }) {
            return ShortcutConfiguration.option(for: profile.shortcutKeyCode)
        }
        return settingsVM.selectedShortcutOption
    }

    private func finish() {
        if let onFinish {
            onFinish()
        } else {
            dismiss()
        }
    }

    private func quickPickButton(letter: String) -> some View {
        let option = ShortcutConfiguration.option(forLetter: letter)
        let isSelected = option.carbonKeyCode == pendingOption.carbonKeyCode

        return Button {
            select(option)
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

    private func startKeyCapture() {
        stopKeyCapture()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyPress(event)
            return nil
        }
    }

    private func stopKeyCapture() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func handleKeyPress(_ event: NSEvent) {
        if event.keyCode == 53 {
            finish()
            return
        }

        let forbiddenModifiers = event.modifierFlags.intersection([.command, .control, .option, .function])
        if !forbiddenModifiers.isEmpty {
            NSSound.beep()
            return
        }

        guard let input = event.charactersIgnoringModifiers?.uppercased(), input.count == 1 else {
            NSSound.beep()
            return
        }

        let scalar = input.unicodeScalars.first?.value ?? 0
        guard scalar >= 65, scalar <= 90 else {
            NSSound.beep()
            return
        }

        guard let option = settingsVM.shortcutOptions.first(where: { $0.letter == input }) else {
            NSSound.beep()
            return
        }

        select(option)
    }

    private func select(_ option: ShortcutKeyOption) {
        pendingOption = option
        updateCollisionMessage()
    }

    private func updateCollisionMessage() {
        if settingsVM.isShortcutLetterAvailable(pendingOption.carbonKeyCode, excludingProfile: profileID) {
            collisionMessage = nil
        } else {
            collisionMessage = "Another profile already uses ⌘⇧\(pendingOption.letter). Pick a different letter."
        }
    }

    private func saveAndClose() {
        if pendingOption.carbonKeyCode != currentOption.carbonKeyCode {
            settingsVM.setShortcut(pendingOption, forProfile: profileID)
            onShortcutChanged()
        }
        finish()
    }
}
