import ControlVCore
import SwiftUI

/// "Advanced settings" panel — replaces the popover content in-place (same
/// pattern as SignInView / DebugSheet) so we don't hit the NSPopover + .sheet
/// focus bugs the rest of the app has already been bitten by.
///
/// The primary purpose today is managing multiple shortcut profiles (up to
/// `TranslationProfile.maxProfiles`). Each card edits one profile's language,
/// tone, custom prompt, and its own global shortcut letter. Profile 1 mirrors
/// the primary popover UI — the user can add or remove profiles 2 and 3 from
/// here.
@MainActor
struct AdvancedSettingsView: View {
    @Bindable var settingsVM: SettingsViewModel
    @Bindable var translatorVM: TranslatorViewModel
    let onClose: () -> Void

    @State private var shortcutSheetProfileID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Text("Give each profile its own shortcut, target language, and tone. Up to \(TranslationProfile.maxProfiles) profiles.")
                .font(.footnote.weight(.medium))
                .foregroundStyle(MenuTheme.subtleText)

            ForEach(settingsVM.settings.profiles) { profile in
                profileCard(profile)
            }

            if settingsVM.canAddProfile {
                Button {
                    _ = settingsVM.addProfile()
                    translatorVM.refreshHotkeyRegistration()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add profile")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(MenuTheme.cyan.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(MenuTheme.cyan.opacity(0.35), lineWidth: 1)
                    )
                    .foregroundStyle(MenuTheme.cyan)
                }
                .buttonStyle(.plain)
            } else {
                Text("Profile cap reached. Remove one to add another.")
                    .font(.caption)
                    .foregroundStyle(MenuTheme.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .sheet(isPresented: shortcutSheetBinding) {
            ShortcutSettingsView(
                settingsVM: settingsVM,
                profileID: shortcutSheetProfileID
            ) {
                translatorVM.refreshHotkeyRegistration()
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Shortcut profiles")
                .font(.headline.weight(.semibold))

            Spacer()

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(MenuTheme.subtleText)
            }
            .buttonStyle(.plain)
        }
    }

    private var shortcutSheetBinding: Binding<Bool> {
        Binding(
            get: { shortcutSheetProfileID != nil },
            set: { presented in
                if !presented { shortcutSheetProfileID = nil }
            }
        )
    }

    // MARK: - Per-profile card

    private func profileCard(_ profile: TranslationProfile) -> some View {
        let index = settingsVM.settings.profiles.firstIndex(where: { $0.id == profile.id }) ?? 0
        return MenuCard {
            HStack {
                Text("Profile \(index + 1)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if index > 0 {
                    Button {
                        settingsVM.removeProfile(id: profile.id)
                        translatorVM.refreshHotkeyRegistration()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }

            NativeMenuDivider()

            HStack {
                NativeSectionLabel(systemName: "keyboard", tint: MenuTheme.cyan, title: "Shortcut")
                Spacer()
                Button {
                    shortcutSheetProfileID = profile.id
                } label: {
                    HStack(spacing: 6) {
                        ShortcutBadge(keys: ["⌘", "⇧", profile.shortcutLetter])
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MenuTheme.tertiaryText)
                    }
                }
                .buttonStyle(.plain)
            }

            HStack {
                NativeSectionLabel(systemName: "message.fill", tint: MenuTheme.cyan, title: "Translate to")
                Spacer()
                LanguageDropdown(selection: languageBinding(for: profile.id))
            }

            VStack(alignment: .leading, spacing: 8) {
                NativeSectionLabel(systemName: "slider.horizontal.3", tint: MenuTheme.cyan, title: "Tone")
                ToneSelector(selection: toneBinding(for: profile.id))

                if profile.tone == .custom {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Custom prompt")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(MenuTheme.subtleText)
                        NativeControlSurface(cornerRadius: 12, horizontalPadding: 10, verticalPadding: 9) {
                            TextField(
                                "Example: Translate in a clear, friendly startup tone.",
                                text: customTonePromptBinding(for: profile.id),
                                axis: .vertical
                            )
                            .lineLimit(3...4)
                            .textFieldStyle(.plain)
                            .font(.subheadline)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Bindings that route to the correct profile

    private func languageBinding(for id: UUID) -> Binding<SupportedLanguage> {
        Binding(
            get: {
                settingsVM.settings.profiles.first(where: { $0.id == id })?.targetLanguage ?? .english
            },
            set: { newValue in
                settingsVM.updateProfile(id: id, targetLanguage: newValue)
                translatorVM.refreshHotkeyRegistration()
            }
        )
    }

    private func toneBinding(for id: UUID) -> Binding<Tone> {
        Binding(
            get: {
                settingsVM.settings.profiles.first(where: { $0.id == id })?.tone ?? .original
            },
            set: { newValue in
                settingsVM.updateProfile(id: id, tone: newValue)
                translatorVM.refreshHotkeyRegistration()
            }
        )
    }

    private func customTonePromptBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: {
                settingsVM.settings.profiles.first(where: { $0.id == id })?.customTonePrompt ?? ""
            },
            set: { newValue in
                settingsVM.updateProfile(id: id, customTonePrompt: newValue)
            }
        )
    }
}
