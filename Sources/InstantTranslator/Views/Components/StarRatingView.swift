import SwiftUI

/// Five tappable stars. `rating` is nil until the user picks one.
struct StarRatingView: View {
    @Binding var rating: Int?
    var size: CGFloat = 20
    var onPick: ((Int) -> Void)? = nil

    private let starColor = Color(red: 0.98, green: 0.74, blue: 0.20)

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { value in
                Button {
                    rating = value
                    onPick?(value)
                } label: {
                    Image(systemName: value <= (rating ?? 0) ? "star.fill" : "star")
                        .font(.system(size: size, weight: .medium))
                        .foregroundStyle(value <= (rating ?? 0) ? starColor : MenuTheme.tertiaryText)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .help("\(value) star\(value == 1 ? "" : "s")")
            }
        }
    }
}
