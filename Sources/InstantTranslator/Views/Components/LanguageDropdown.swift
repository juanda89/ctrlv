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
            NativeControlSurface(cornerRadius: 11, horizontalPadding: 10, verticalPadding: 6) {
                HStack(spacing: 6) {
                    Text(selection.rawValue)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MenuTheme.subtleText)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: 124)
    }
}
