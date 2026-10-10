import Foundation

public enum TranslationError: LocalizedError {
    case noTextSelected
    case accessibilityNotGranted
    case backendNotConfigured
    case networkError(underlying: Error)
    case apiError(statusCode: Int, message: String)
    case rateLimited(provider: ProviderType, retryAfter: Int?)
    case trialExpired
    case trialQuotaExceeded(remaining: Int)
    case trialTextTooLong(maxWords: Int)
    case replacementFailed

    public var errorDescription: String? {
        switch self {
        case .noTextSelected:
            "No text selected"
        case .accessibilityNotGranted:
            "Accessibility permission required. Enable in System Settings → Privacy → Accessibility."
        case .backendNotConfigured:
            "Translation service is not configured yet."
        case .networkError(let error):
            "Network error: \(error.localizedDescription)"
        case .apiError(let code, let message):
            "API error (\(code)): \(message)"
        case .rateLimited(let provider, let retry):
            if let retry { "\(provider.rawValue) rate limited. Retry in \(retry)s." }
            else { "\(provider.rawValue) rate limited. Try again shortly." }
        case .trialExpired:
            "Your free trial has ended. Subscribe to keep translating."
        case .trialQuotaExceeded:
            "You've used today's \(TrialTranslationService.dailyLimit) free translations. Subscribe to keep translating."
        case .trialTextTooLong(let maxWords):
            "The free trial translates up to \(maxWords) words at a time. Subscribe to translate longer texts."
        case .replacementFailed:
            "Could not replace selected text"
        }
    }

    /// Only a subscription gets past these: retrying cannot, so clients
    /// offer the upgrade instead of "Try again".
    public var requiresSubscription: Bool {
        switch self {
        case .trialExpired, .trialQuotaExceeded, .trialTextTooLong: true
        default: false
        }
    }

    /// The server's trial rejections (`supabase/functions/_shared/access.ts`),
    /// matched on their exact wording so every client shows the upgrade
    /// instead of a raw status. Anything else stays a generic error.
    public static func trialRejection(statusCode: Int, message: String?) -> TranslationError? {
        guard let message else { return nil }
        switch statusCode {
        case 403 where message == "Trial expired":
            return .trialExpired
        case 429 where message.hasPrefix("Trial daily limit"):
            return .trialQuotaExceeded(remaining: 0)
        case 429 where message.hasPrefix("Trial text exceeds"):
            let characters = Int(message.filter(\.isNumber)) ?? TrialTranslationService.maxCharacters
            return .trialTextTooLong(maxWords: characters / 6)
        default:
            return nil
        }
    }
}
