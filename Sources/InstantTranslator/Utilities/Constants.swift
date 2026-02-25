import Foundation

enum Constants {
    static let appName = "ctrl+v"
    static let clipboardRestoreDelay: UInt64 = 2_000_000_000 // 2 seconds in nanoseconds
    static let copyWaitDelay: UInt64 = 150_000_000 // 150ms in nanoseconds
    static let defaultFeedbackURL = "https://control-v.info/feedback"
    static let defaultLemonCheckoutURL = "https://control-v.info/upgrade"
    static let defaultLemonPortalURL = "https://control-v.info/manage"
    static let defaultLemonLicenseAPIBaseURL = "https://api.lemonsqueezy.com"
    static let updatesFeedURL = configuredURL(for: "SUFeedURL")
    static let feedbackURL = configuredURL(for: "CtrlVFeedbackURL") ?? URL(string: defaultFeedbackURL)
    static let lemonCheckoutURL = configuredURL(for: "CtrlVLemonCheckoutURL") ?? URL(string: defaultLemonCheckoutURL)
    static let lemonPortalURL = configuredURL(for: "CtrlVLemonPortalURL") ?? URL(string: defaultLemonPortalURL)
    static let lemonLicenseAPIBaseURL = configuredURL(for: "CtrlVLemonLicenseAPIBaseURL") ?? URL(string: defaultLemonLicenseAPIBaseURL)

    private static func configuredURL(for key: String) -> URL? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }
}
