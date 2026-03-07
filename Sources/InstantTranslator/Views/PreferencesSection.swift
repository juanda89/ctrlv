import SwiftUI

struct PreferencesSection: View {
    @Bindable var settingsVM: SettingsViewModel

    var body: some View {
        MenuCard {
            HStack {
                NativeSectionLabel(systemName: "message.fill", tint: MenuTheme.blue, title: "Translate to")

                Spacer()

                LanguageDropdown(selection: $settingsVM.settings.targetLanguage)
            }

            NativeMenuDivider()

            VStack(alignment: .leading, spacing: 8) {
                NativeSectionLabel(systemName: "slider.horizontal.3", tint: .indigo, title: "Tone")
                ToneSelector(selection: $settingsVM.settings.tone)

                if settingsVM.settings.tone == .custom {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Custom prompt")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(MenuTheme.subtleText)

                        NativeControlSurface(cornerRadius: 12, horizontalPadding: 10, verticalPadding: 9) {
                            TextField(
                                "Example: Translate in a clear, friendly startup tone with short sentences.",
                                text: $settingsVM.settings.customTonePrompt,
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
