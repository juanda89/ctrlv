import Foundation
import TelemetryDeck

enum TelemetryService {

    private(set) static var isConfigured = false
    private(set) static var signalsSentCount = 0
    private(set) static var lastSignalName: String?
    private(set) static var lastSignalAt: Date?
    static let appID = "EAF0D438-86C4-47B0-B489-FD8ED54ECB89"

    static func configure(appID: String) {
        let config = TelemetryDeck.Config(appID: appID)
        TelemetryDeck.initialize(config: config)
        isConfigured = true
    }

    private static func send(_ signalName: String, parameters: [String: String] = [:]) {
        guard isConfigured else { return }
        TelemetryDeck.signal(signalName, parameters: parameters)
        signalsSentCount += 1
        lastSignalName = signalName
        lastSignalAt = Date()
    }

    static func sendTestPing() {
        send("Debug.testPing", parameters: ["timestamp": ISO8601DateFormatter().string(from: Date())])
    }

    // MARK: - Translation

    static func trackTranslationCompleted(
        provider: ProviderType,
        targetLanguage: SupportedLanguage,
        tone: Tone,
        method: String,
        textLength: Int
    ) {
        let bucket = textLength < 50 ? "short" : textLength < 200 ? "medium" : "long"
        send(
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
        send(
            "Translation.failed",
            parameters: [
                "provider": provider.rawValue,
                "errorType": errorType,
            ]
        )
    }

    static func trackTranslationRateLimited(provider: ProviderType, retryAfter: Int?) {
        send(
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
            send(
                "License.trialDaysRemaining",
                parameters: ["daysRemaining": String(days), "urgency": urgency]
            )
        case .active(let planName, _, let isOfflineGrace):
            send(
                "License.activated",
                parameters: [
                    "planName": planName ?? "unknown",
                    "isOfflineGrace": String(isOfflineGrace),
                ]
            )
        case .expired:
            send("License.expired")
        case .invalid(let reason):
            send("License.invalid", parameters: ["reason": reason])
        case .checking:
            break
        }
    }

    // MARK: - Accessibility

    static func trackAccessibilityStatus(granted: Bool) {
        send(
            "Accessibility.statusOnLaunch",
            parameters: ["granted": String(granted)]
        )
    }

    static func trackAccessibilityResetTriggered() {
        send("Accessibility.resetTriggered")
    }

    // MARK: - Settings

    static func trackLanguageChanged(_ language: SupportedLanguage) {
        send(
            "Settings.languageChanged",
            parameters: ["targetLanguage": language.rawValue]
        )
    }

    static func trackToneChanged(_ tone: Tone) {
        send(
            "Settings.toneChanged",
            parameters: ["tone": tone.rawValue]
        )
    }

    static func trackProviderChanged(_ provider: ProviderType) {
        send(
            "Settings.providerChanged",
            parameters: ["provider": provider.rawValue]
        )
    }

    static func trackAutoPasteToggled(enabled: Bool) {
        send(
            "Settings.autoPasteToggled",
            parameters: ["enabled": String(enabled)]
        )
    }

    static func trackAPIKeyAdded(provider: ProviderType) {
        send(
            "Settings.apiKeyAdded",
            parameters: ["provider": provider.rawValue]
        )
    }
}
