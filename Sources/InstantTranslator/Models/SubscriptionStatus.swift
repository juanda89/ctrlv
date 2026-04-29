import Foundation

enum SubscriptionStatusValue: String, Codable {
    case trial
    case active
    case pastDue = "past_due"
    case canceled
    case expired
    case unknown

    init(raw: String?) {
        switch raw?.lowercased() {
        case "active": self = .active
        case "trial", "trialing": self = .trial
        case "past_due": self = .pastDue
        case "canceled", "cancelled": self = .canceled
        case "expired": self = .expired
        default: self = .unknown
        }
    }

    /// Whether this status grants access to translation.
    var canTranslate: Bool {
        switch self {
        case .active, .trial:
            return true
        case .pastDue, .canceled, .expired, .unknown:
            return false
        }
    }
}

struct SubscriptionStatus: Codable, Equatable {
    let status: SubscriptionStatusValue
    let planName: String?
    let trialDaysRemaining: Int?

    init(status: SubscriptionStatusValue, planName: String?, trialDaysRemaining: Int?) {
        self.status = status
        self.planName = planName
        self.trialDaysRemaining = trialDaysRemaining
    }
}

/// Persisted account record stored encrypted in AccountStore.
struct StoredAccountRecord: Codable, Equatable {
    var email: String
    var sessionToken: String
    var subscriptionStatus: String?
    var planName: String?
    var lastValidatedAt: Date?
}
