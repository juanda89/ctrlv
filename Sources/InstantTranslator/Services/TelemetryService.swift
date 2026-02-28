import Foundation
import TelemetryDeck

enum TelemetryService {

    // MARK: - Translation

    static func trackTranslationCompleted(
        provider: ProviderType,
        targetLanguage: SupportedLanguage,
        tone: Tone,
        method: String,
        textLength: Int
    ) {
        let bucket = textLength < 50 ? "short" : textLength < 200 ? "medium" : "long"
        TelemetryDeck.signal(
            "Translation.completed",
            parameters: [
                "provider": provider.rawValue,
                "targetLanguage": targetLanguage.rawValue,
                "tone": tone.rawValue,
                "method": method,
                "textLengthBucket": bucket,
            ]
        )
    }

    static func trackTranslationFailed(provider: ProviderType, errorType: String) {
        TelemetryDeck.signal(
            "Translation.failed",
            parameters: [
                "provider": provider.rawValue,
                "errorType": errorType,
            ]
        )
    }

    static func trackTranslationRateLimited(provider: ProviderType, retryAfter: Int?) {
        TelemetryDeck.signal(
            "Translation.rateLimited",
            parameters: [
                "provider": provider.rawValue,
                "retryAfter": retryAfter.map(String.init) ?? "unknown",
            ]
        )
    }

    // MARK: - License

    static func trackLicenseState(_ state: LicenseState) {
        switch state {
        case .trial(let days):
            let urgency = days <= 3 ? "critical" : days <= 7 ? "warning" : "healthy"
            TelemetryDeck.signal(
                "License.trialDaysRemaining",
                parameters: ["daysRemaining": String(days), "urgency": urgency]
            )
        case .active(let planName, _, let isOfflineGrace):
            TelemetryDeck.signal(
                "License.activated",
                parameters: [
                    "planName": planName ?? "unknown",
                    "isOfflineGrace": String(isOfflineGrace),
                ]
            )
        case .expired:
            TelemetryDeck.signal("License.expired")
        case .invalid(let reason):
            TelemetryDeck.signal("License.invalid", parameters: ["reason": reason])
        case .checking:
            break
        }
    }

    // MARK: - Accessibility

    static func trackAccessibilityStatus(granted: Bool) {
        TelemetryDeck.signal(
            "Accessibility.statusOnLaunch",
            parameters: ["granted": String(granted)]
        )
    }

    static func trackAccessibilityResetTriggered() {
        TelemetryDeck.signal("Accessibility.resetTriggered")
    }

    // MARK: - Settings

    static func trackLanguageChanged(_ language: SupportedLanguage) {
        TelemetryDeck.signal(
            "Settings.languageChanged",
            parameters: ["targetLanguage": language.rawValue]
        )
    }

    static func trackToneChanged(_ tone: Tone) {
        TelemetryDeck.signal(
            "Settings.toneChanged",
            parameters: ["tone": tone.rawValue]
        )
    }

    static func trackProviderChanged(_ provider: ProviderType) {
        TelemetryDeck.signal(
            "Settings.providerChanged",
            parameters: ["provider": provider.rawValue]
        )
    }

    static func trackAutoPasteToggled(enabled: Bool) {
        TelemetryDeck.signal(
            "Settings.autoPasteToggled",
            parameters: ["enabled": String(enabled)]
        )
    }

    static func trackAPIKeyAdded(provider: ProviderType) {
        TelemetryDeck.signal(
            "Settings.apiKeyAdded",
            parameters: ["provider": provider.rawValue]
        )
    }
}
