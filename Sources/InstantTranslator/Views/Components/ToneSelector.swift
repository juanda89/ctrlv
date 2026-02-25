import SwiftUI

struct ToneSelector: View {
    @Binding var selection: Tone
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Tone.allCases) { tone in
                toneButton(tone)
            }
        }
    }

    private func toneButton(_ tone: Tone) -> some View {
        Button {
            selection = tone
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon(for: tone))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selection == tone ? MenuTheme.blue : .secondary)

                Text(tone.rawValue)
                    .font(.system(size: 10, weight: selection == tone ? .semibold : .medium))
                    .foregroundStyle(selection == tone ? MenuTheme.blue : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selection == tone ? MenuTheme.blue.opacity(0.14) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(selection == tone ? MenuTheme.blue.opacity(0.35) : Color.primary.opacity(0.1), lineWidth: 1)
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
