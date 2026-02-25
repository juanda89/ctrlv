import SwiftUI

struct LanguageDropdown: View {
    @Binding var selection: SupportedLanguage

    var body: some View {
        Menu {
            ForEach(SupportedLanguage.allCases) { language in
                Button(language.rawValue) {
                    selection = language
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selection.rawValue)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .frame(width: 118)
    }
}
