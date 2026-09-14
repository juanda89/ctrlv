import Foundation

public enum Constants {
    public static let appName = "ctrl+v"
    public static let clipboardRestoreDelay: UInt64 = 1_200_000_000 // 1.2 seconds in nanoseconds
    public static let axVerificationDelay: UInt64 = 45_000_000 // 45ms in nanoseconds
    public static let defaultFeedbackURL = "mailto:info@control-v.info?subject=ctrl%2Bv%20Feedback"
    public static let defaultManualUpdateURL = "https://control-v.info/download.html?autostart=1"
    public static let defaultAuthAPIBaseURL = "https://hdfhonbgkkiffhkwoivd.functions.supabase.co"
    // Compiled-in default so app extensions (Share, Keyboard) work even though
    // Bundle.main resolves to the extension's own Info.plist, not the app's.
    public static let defaultTranslationAPIURL = "https://hdfhonbgkkiffhkwoivd.functions.supabase.co/translate"
    // Display label only. The actual model is chosen server-side per request
    // (OPENROUTER_MODELS fallback chain in the translate Edge Function), so
    // the client cannot know it ahead of time — don't show a specific model
    // name here or debug output will lie when the server chain changes.
    public static let hostedModelName = "auto (server-selected)"
    public static let hostedEngineName = "OpenRouter"
    public static let updatesFeedURL = configuredURL(for: "SUFeedURL")
    public static let manualUpdateURL = configuredURL(for: "CtrlVManualUpdateURL") ?? URL(string: defaultManualUpdateURL)
    public static let feedbackURL = configuredURL(for: "CtrlVFeedbackURL") ?? URL(string: defaultFeedbackURL)
    public static let translationAPIURL = configuredURL(for: "CtrlVTranslationAPIURL") ?? URL(string: defaultTranslationAPIURL)
    public static let authAPIBaseURL = configuredURL(for: "CtrlVAuthAPIBaseURL") ?? URL(string: defaultAuthAPIBaseURL)

    private static func configuredURL(for key: String) -> URL? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }
}
