import ControlVCore
import SwiftUI

/// Language, tone and custom prompt of the profile selected in the tabs.
struct PreferencesSection: View {
    @Bindable var settingsVM: SettingsViewModel

    var body: some View {
        MenuCard {
            HStack {
                NativeSectionLabel(systemName: "message.fill", tint: MenuTheme.cyan, title: "Translate to")

                Spacer()

                LanguageDropdown(selection: $settingsVM.selectedTargetLanguage)
            }

            NativeMenuDivider()

            VStack(alignment: .leading, spacing: 8) {
                NativeSectionLabel(systemName: "slider.horizontal.3", tint: MenuTheme.cyan, title: "Tone")
                ToneSelector(selection: $settingsVM.selectedTone)

                if settingsVM.selectedTone == .custom {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Custom prompt")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(MenuTheme.subtleText)

                        NativeControlSurface(cornerRadius: 12, horizontalPadding: 10, verticalPadding: 9) {
                            TextField(
                                "Example: Translate in a clear, friendly startup tone with short sentences.",
                                text: $settingsVM.selectedCustomTonePrompt,
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
}
