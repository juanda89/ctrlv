import SwiftUI

struct ToneSelector: View {
    @Binding var selection: Tone
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Tone.allCases) { tone in
                toneButton(tone)
            }
        }
    }

    private func toneButton(_ tone: Tone) -> some View {
        Button {
            selection = tone
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon(for: tone))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selection == tone ? MenuTheme.blue : MenuTheme.subtleText)

                Text(tone.rawValue)
                    .font(.caption2.weight(selection == tone ? .semibold : .medium))
                    .foregroundStyle(selection == tone ? MenuTheme.blue : MenuTheme.subtleText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selection == tone ? MenuTheme.selectedFill : MenuTheme.controlFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(selection == tone ? MenuTheme.selectedBorder : MenuTheme.controlBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func icon(for tone: Tone) -> String {
        switch tone {
        case .original:
            return "doc.text"
        case .formal:
            return "briefcase"
        case .casual:
            return "bubble.left.and.bubble.right.fill"
        case .concise:
            return "scissors"
        case .custom:
            return "wand.and.stars"
        }
    }
}
