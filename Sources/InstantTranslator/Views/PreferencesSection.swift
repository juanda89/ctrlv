import SwiftUI

struct PreferencesSection: View {
    @Bindable var settingsVM: SettingsViewModel

    var body: some View {
        MenuCard {
            HStack {
                HStack(spacing: 8) {
                    IconBubble(systemName: "message.fill", tint: .blue)
                    Text("Translate to")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                LanguageDropdown(selection: $settingsVM.settings.targetLanguage)
            }

            Divider()
                .overlay(Color.primary.opacity(0.08))

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    IconBubble(systemName: "slider.horizontal.3", tint: .indigo)
                    Text("Tone")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                ToneSelector(selection: $settingsVM.settings.tone)

                if settingsVM.settings.tone == .custom {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Custom prompt")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)

                        TextField(
                            "Example: Translate in a clear, friendly startup tone with short sentences.",
                            text: $settingsVM.settings.customTonePrompt,
                            axis: .vertical
                        )
                        .lineLimit(3...4)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                    }
                }
            }
        }
    }
}
