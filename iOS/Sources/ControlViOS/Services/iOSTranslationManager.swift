import ControlVCore
import Foundation
import Observation

@MainActor
@Observable
final class iOSTranslationManager {
    private let licenseService: LicenseService
    // App Group defaults so the main app and both extensions share ONE installID —
    // trial limits are tracked per installID on the backend.
    private let deviceIdentity = DeviceIdentityStore(
        userDefaults: UserDefaults(suiteName: iOSSettingsStore.appGroup) ?? .standard
    )

    init(licenseService: LicenseService) {
        self.licenseService = licenseService
    }

    func translate(
        text: String,
        targetLanguage: SupportedLanguage,
        tone: Tone,
        customTonePrompt: String?
    ) async throws -> String {
        guard licenseService.state.canTranslate else {
            throw TranslationError.trialExpired
        }

        guard let endpoint = Constants.translationAPIURL else {
            throw TranslationError.backendNotConfigured
        }

        let provider = CtrlVCloudProvider(
            endpoint: endpoint,
            installID: deviceIdentity.currentInstallID(),
            sessionToken: licenseService.storedSessionToken
        )

        let service = TranslationService(provider: provider)
        let request = TranslationRequest(
            text: text,
            targetLanguage: targetLanguage,
            tone: tone,
            customTonePrompt: customTonePrompt
        )
        let response = try await service.translate(request)

        // Track local trial usage so iOS in-app translates count too.
        TrialTranslationService.recordTranslation()

        return response.translatedText
    }
}
