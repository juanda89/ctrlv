import Foundation

public enum SubscriptionStatusValue: String, Codable, Sendable {
    case trial
    case active
    case pastDue = "past_due"
    case canceled
    case expired
    case unknown

    public init(raw: String?) {
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
    public var canTranslate: Bool {
        switch self {
        case .active, .trial:
            return true
        case .pastDue, .canceled, .expired, .unknown:
            return false
        }
    }
}

public struct SubscriptionStatus: Codable, Equatable, Sendable {
    public let status: SubscriptionStatusValue
    public let planName: String?
    public let trialDaysRemaining: Int?

    public init(status: SubscriptionStatusValue, planName: String?, trialDaysRemaining: Int?) {
        self.status = status
        self.planName = planName
        self.trialDaysRemaining = trialDaysRemaining
    }
}

/// Persisted account record stored encrypted in AccountStore.
public struct StoredAccountRecord: Codable, Equatable, Sendable {
    public var email: String
    public var sessionToken: String
    public var subscriptionStatus: String?
    public var planName: String?
    public var lastValidatedAt: Date?

    public init(
        email: String,
        sessionToken: String,
        subscriptionStatus: String?,
        planName: String?,
        lastValidatedAt: Date?
    ) {
        self.email = email
        self.sessionToken = sessionToken
        self.subscriptionStatus = subscriptionStatus
        self.planName = planName
        self.lastValidatedAt = lastValidatedAt
    }
}
