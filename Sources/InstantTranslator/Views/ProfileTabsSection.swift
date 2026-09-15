import ControlVCore
import SwiftUI

/// Tab strip for shortcut profiles, shown right under the subscription card.
/// Selecting a tab only changes which profile the sections below EDIT; which
/// profile translates is decided by the shortcut the user presses.
@MainActor
struct ProfileTabsSection: View {
    @Bindable var settingsVM: SettingsViewModel
    @Bindable var translatorVM: TranslatorViewModel

    var body: some View {
        MenuCard {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(Array(settingsVM.settings.profiles.enumerated()), id: \.element.id) { index, profile in
                        tab(index: index, profile: profile)
                    }

                    if settingsVM.canAddProfile {
                        NativeAccessoryButton(systemName: "plus", tint: MenuTheme.cyan, size: 26) {
                            settingsVM.addProfileAndSelect()
                            translatorVM.refreshHotkeyRegistration()
                        }
                        .help("Add a profile with its own shortcut, language and tone")
                    }
                }
                // The scroll view clips exactly at its content edge; the pills'
                // 1pt stroke is centered on their edge, so without this inset
                // half of it was cut off on the left/top/bottom — visible as
                // flattened corners on the selected (blue) pill when it is the
                // first tab.
                .padding(1)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func tab(index: Int, profile: TranslationProfile) -> some View {
        let isSelected = profile.id == settingsVM.selectedProfileID
        return HStack(spacing: 4) {
            Button {
                settingsVM.selectProfile(profile.id)
            } label: {
                HStack(spacing: 5) {
                    Text("Profile \(index + 1)")
                        .font(.subheadline.weight(isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? MenuTheme.blue : .primary)
                    Text("⌘⇧\(profile.shortcutLetter)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isSelected ? MenuTheme.blue.opacity(0.8) : MenuTheme.tertiaryText)
                }
                .lineLimit(1)
                .padding(.leading, 9)
                .padding(.trailing, index > 0 && isSelected ? 2 : 9)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()

            // Only the selected, non-primary tab exposes its remove control:
            // keeps the strip compact and makes accidental deletes unlikely.
            if index > 0, isSelected {
                Button {
                    settingsVM.removeProfile(id: profile.id)
                    translatorVM.refreshHotkeyRegistration()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(MenuTheme.subtleText)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove Profile \(index + 1)")
                .padding(.trailing, 4)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? MenuTheme.selectedFill : MenuTheme.controlFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(isSelected ? MenuTheme.selectedBorder : MenuTheme.controlBorder, lineWidth: 1)
        )
    }
}
