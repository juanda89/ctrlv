import Foundation
import Observation

/// Decides when the popover should actively invite the user to rate the app:
/// after a real amount of use, once, and never again after they answered or
/// dismissed it. The feedback card itself is always visible; this only
/// controls the emphasized "invite" state.
@Observable
public final class FeedbackPromptTracker {
    public static let inviteThreshold = 25

    private let defaults: UserDefaults
    private let countKey = "feedback.translationCount"
    private let dismissedKey = "feedback.inviteDismissed"
    private let submittedAtKey = "feedback.submittedAt"

    public private(set) var translationCount: Int
    public private(set) var isDismissed: Bool
    public private(set) var submittedAt: Date?

    public init(userDefaults: UserDefaults = .standard) {
        self.defaults = userDefaults
        self.translationCount = userDefaults.integer(forKey: countKey)
        self.isDismissed = userDefaults.bool(forKey: dismissedKey)
        self.submittedAt = userDefaults.object(forKey: submittedAtKey) as? Date
    }

    public var hasSubmitted: Bool { submittedAt != nil }

    public var shouldInvite: Bool {
        !hasSubmitted && !isDismissed && translationCount >= Self.inviteThreshold
    }

    public func recordTranslation() {
        translationCount += 1
        defaults.set(translationCount, forKey: countKey)
    }

    public func markDismissed() {
        isDismissed = true
        defaults.set(true, forKey: dismissedKey)
    }

    public func markSubmitted(at date: Date = Date()) {
        submittedAt = date
        defaults.set(date, forKey: submittedAtKey)
    }
}
