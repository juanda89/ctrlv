import Foundation

enum LicenseState {
    case checking
    case trial(daysRemaining: Int)
    case expired
    case active(planName: String?, validatedAt: Date, isOfflineGrace: Bool)
    case invalid(reason: String)

    var canTranslate: Bool {
        switch self {
        case .trial, .active:
            true
        case .checking, .expired, .invalid:
            false
        }
    }

    var statusText: String {
        switch self {
        case .checking:
            return "Checking license"
        case .trial(let days):
            return "Trial: \(days) days remaining"
        case .expired:
            return "Trial expired"
        case .active(let planName, _, let isOfflineGrace):
            let base: String
            if let planName, !planName.isEmpty {
                base = "Active: \(planName)"
            } else {
                base = "Active license"
            }
            return isOfflineGrace ? "\(base) (offline mode)" : base
        case .invalid(let reason):
            return "Invalid license: \(reason)"
        }
    }
}
