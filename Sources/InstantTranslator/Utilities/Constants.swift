import Foundation

enum Constants {
    static let appName = "ctrl+v"
    static let clipboardRestoreDelay: UInt64 = 1_200_000_000 // 1.2 seconds in nanoseconds
    static let copyWaitDelay: UInt64 = 90_000_000 // 90ms in nanoseconds
    static let axVerificationDelay: UInt64 = 45_000_000 // 45ms in nanoseconds
    static let defaultFeedbackURL = "mailto:info@control-v.info?subject=ctrl%2Bv%20Feedback"
    static let defaultManualUpdateURL = "https://control-v.info/download.html?autostart=1"
    static let defaultLemonCheckoutURL = "https://control-v.info/upgrade"
    static let defaultLemonPortalURL = "https://control-v.info/manage"
    static let defaultLemonLicenseAPIBaseURL = "https://api.lemonsqueezy.com"
    static let hostedModelName = "moonshotai/kimi-k2.5"
    static let hostedEngineName = "OpenRouter"
    static let updatesFeedURL = configuredURL(for: "SUFeedURL")
    static let manualUpdateURL = configuredURL(for: "CtrlVManualUpdateURL") ?? URL(string: defaultManualUpdateURL)
    static let feedbackURL = configuredURL(for: "CtrlVFeedbackURL") ?? URL(string: defaultFeedbackURL)
    static let translationAPIURL = configuredURL(for: "CtrlVTranslationAPIURL")
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
