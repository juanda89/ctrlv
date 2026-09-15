import Foundation

public enum FeedbackCategory: String, Codable, CaseIterable, Identifiable {
    case bug
    case idea
    case praise
    case other

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .bug: return "Bug"
        case .idea: return "Idea"
        case .praise: return "Love it"
        case .other: return "Other"
        }
    }
}

/// One piece of in-app feedback, exactly as sent to `submit-feedback`.
public struct FeedbackSubmission: Codable, Equatable {
    public var rating: Int?
    public var category: FeedbackCategory
    public var message: String
    public var contactEmail: String?
    public var installID: String
    public var sessionToken: String?
    public var appVersion: String
    public var platform: String

    public init(
        rating: Int?,
        category: FeedbackCategory,
        message: String,
        contactEmail: String?,
        installID: String,
        sessionToken: String?,
        appVersion: String,
        platform: String = "macos"
    ) {
        self.rating = rating
        self.category = category
        self.message = message
        self.contactEmail = contactEmail
        self.installID = installID
        self.sessionToken = sessionToken
        self.appVersion = appVersion
        self.platform = platform
    }
}
