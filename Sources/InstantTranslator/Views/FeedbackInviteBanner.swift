import ControlVCore
import SwiftUI

/// One-time invite shown near the top of the popover once the user has
/// translated enough to have an opinion. Tapping a star opens the form with
/// that rating; "Later" hides it for good.
@MainActor
struct FeedbackInviteBanner: View {
    @Bindable var tracker: FeedbackPromptTracker
    let onOpen: (Int?) -> Void

    @State private var pendingRating: Int?

    var body: some View {
        MenuCard {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enjoying ctrl+v?")
                        .font(.subheadline.weight(.semibold))
                    StarRatingView(rating: $pendingRating, size: 18) { picked in
                        onOpen(picked)
                        pendingRating = nil
                    }
                }
                Spacer(minLength: 8)
                Button("Later") { tracker.markDismissed() }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(MenuTheme.tertiaryText)
                    .focusEffectDisabled()
            }
        }
    }
}
