import Foundation

enum TranslationError: LocalizedError {
    case noTextSelected
    case accessibilityNotGranted
    case apiKeyMissing
    case networkError(underlying: Error)
    case apiError(statusCode: Int, message: String)
    case rateLimited(provider: ProviderType, retryAfter: Int?)
    case trialExpired
    case replacementFailed

    var errorDescription: String? {
        switch self {
        case .noTextSelected:
            "No text selected"
        case .accessibilityNotGranted:
            "Accessibility permission required. Enable in System Settings → Privacy → Accessibility."
        case .apiKeyMissing:
            "API key not configured"
        case .networkError(let error):
            "Network error: \(error.localizedDescription)"
        case .apiError(let code, let message):
            "API error (\(code)): \(message)"
        case .rateLimited(let provider, let retry):
            if let retry { "\(provider.rawValue) rate limited. Retry in \(retry)s." }
            else { "\(provider.rawValue) rate limited. Try again shortly." }
        case .trialExpired:
            "Trial expired. Enter a valid license key to continue."
        case .replacementFailed:
            "Could not replace selected text"
        }
    }
}
