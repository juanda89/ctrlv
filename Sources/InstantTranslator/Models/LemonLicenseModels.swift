import Foundation

enum LemonValidationStatus: String, Codable {
    case active
    case inactive
    case expired
    case disabled
    case canceled
    case unknown

    init(raw: String?) {
        switch raw?.lowercased() {
        case "active":
            self = .active
        case "inactive":
            self = .inactive
        case "expired":
            self = .expired
        case "disabled":
            self = .disabled
        case "cancelled", "canceled":
            self = .canceled
        default:
            self = .unknown
        }
    }
}

struct LemonActivationResult: Equatable {
    let instanceID: String
    let planName: String?
}

struct LemonValidationResult: Equatable {
    let isValid: Bool
    let status: LemonValidationStatus
    let planName: String?
    let instanceID: String?
    let reason: String?
}

struct StoredLicenseRecord: Codable, Equatable {
    var licenseKey: String
    var instanceID: String?
    var lastValidatedAt: Date?
    var lastKnownStatus: String?
    var lastPlanName: String?
}
