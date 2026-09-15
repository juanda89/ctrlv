import ControlVCore
import SwiftUI

/// Always-visible feedback card. Tapping a star opens the form with that
/// rating preselected; "Leave feedback" opens it blank. After enough real
/// use it switches once to an emphasized invite the user can dismiss.
@MainActor
struct FeedbackSection: View {
    @Bindable var tracker: FeedbackPromptTracker
    let onOpen: (Int?) -> Void

    @State private var hoverRating: Int?

    var body: some View {
        MenuCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tracker.shouldInvite ? "Enjoying ctrl+v?" : "How's ctrl+v working for you?")
                        .font(.subheadline.weight(.semibold))
                    Text(tracker.shouldInvite
                         ? "A quick rating helps a lot. Ideas and bugs welcome too."
                         : "Rate it, request a feature, or tell us what broke.")
                        .font(.caption)
                        .foregroundStyle(MenuTheme.subtleText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if tracker.shouldInvite {
                    Button("Later") { tracker.markDismissed() }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(MenuTheme.tertiaryText)
                }
            }

            HStack {
                StarRatingView(rating: $hoverRating, size: 18) { picked in
                    onOpen(picked)
                    hoverRating = nil
                }
                Spacer()
                Button {
                    onOpen(nil)
                } label: {
                    HStack(spacing: 4) {
                        Text("Leave feedback")
                            .font(.caption.weight(.semibold))
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(MenuTheme.blue)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
            }
        }
    }
}
