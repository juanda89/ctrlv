import AppKit
import Foundation
import os

private let log = Logger(subsystem: "com.instanttranslator.app", category: "translator")

enum ProviderRuntimeStatus: Equatable {
    case idle
    case ok(message: String)
    case rateLimited(message: String, retryAfter: Int?)
    case error(message: String)
}

@MainActor
@Observable
final class TranslatorViewModel {
    private(set) var isTranslating = false
    private(set) var lastError: String?
    private(set) var debugHotkeyTriggerCount = 0
    private(set) var debugLastTriggerSource = "none"
    private(set) var debugLastTriggerAt: Date?
    private(set) var debugLastStage = "Idle" {
        didSet { appendDebugEvent(debugLastStage) }
    }
    private(set) var debugEvents: [String] = []
    private(set) var providerStatusByType: [ProviderType: ProviderRuntimeStatus] = [:]

    let settingsVM = SettingsViewModel()

    private let accessibilityService = AccessibilityService()
    private let clipboardService = ClipboardService()
    private let hotkeyService = HotkeyService()
    private let licenseService: LicenseService
    private let debugEventLimit = 40
    private static let debugTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()

    init(licenseService: LicenseService) {
        self.licenseService = licenseService
        setupHotkey()
    }

    private func setupHotkey() {
        hotkeyService.onTrigger = { [weak self] in
            self?.triggerTranslation(source: "hotkey")
        }
        refreshHotkeyRegistration()
    }

    func debugTriggerTranslationFromUI() {
        triggerTranslation(source: "manual-debug-button")
    }

    func refreshHotkeyRegistration() {
        let keyCode = settingsVM.settings.shortcutKeyCode
        let modifiers = ShortcutConfiguration.fixedModifiers
        if settingsVM.settings.shortcutModifiers != UInt(modifiers) {
            settingsVM.settings.shortcutModifiers = UInt(modifiers)
        }
        let shortcut = settingsVM.shortcutDisplay

        hotkeyService.register(
            carbonKeyCode: keyCode,
            carbonModifiers: modifiers,
            shortcutDisplay: shortcut
        )
        debugLastStage = "Hotkey registered (\(shortcut))"
        log.info("Hotkey registered: \(shortcut, privacy: .public)")
    }

    func debugPreviewTranslationIsland() {
        debugLastStage = "Debug: preview island"
        notifyAppDelegate { $0.debugShowTranslationIslandPreview() }
    }

    func providerRuntimeStatus(for provider: ProviderType) -> ProviderRuntimeStatus {
        providerStatusByType[provider] ?? .idle
    }

    func clearProviderRuntimeStatus(for provider: ProviderType) {
        providerStatusByType[provider] = .idle
    }

    func updateProviderRuntimeStatus(from result: APIKeyValidationResult, for provider: ProviderType) {
        switch result.outcome {
        case .valid:
            providerStatusByType[provider] = .ok(message: "OK")
        case .rateLimited:
            let retryText = result.retryAfter.map { "Retry in \($0)s." } ?? "Try again shortly."
            providerStatusByType[provider] = .rateLimited(
                message: "\(provider.rawValue) rate limited. \(retryText)",
                retryAfter: result.retryAfter
            )
        case .invalid, .networkError:
            providerStatusByType[provider] = .error(message: result.message)
        }
    }

    func performTranslation() async {
        guard !isTranslating else {
            debugLastStage = "Skipped: already translating"
            log.warning("Already translating, skipping")
            return
        }
        debugLastStage = "Flow started"

        await licenseService.refreshLicenseStatus(forceNetwork: false)

        // 1. Check license
        guard licenseService.state.canTranslate else {
            debugLastStage = "Blocked: license"
            log.error("License check failed: \(String(describing: self.licenseService.state))")
            lastError = TranslationError.trialExpired.localizedDescription
            notifyAppDelegate { $0.flashMenuBarIcon() }
            return
        }
        debugLastStage = "License OK"
        log.info("License OK")

        // 2. Get API key
        let selectedProvider = settingsVM.settings.selectedProvider
        let apiKey = settingsVM.apiKey(for: selectedProvider)
        guard !apiKey.isEmpty else {
            debugLastStage = "Blocked: missing API key"
            log.error("API key is empty")
            lastError = TranslationError.apiKeyMissing.localizedDescription
            providerStatusByType[selectedProvider] = .error(message: TranslationError.apiKeyMissing.localizedDescription)
            return
        }
        debugLastStage = "API key OK"
        log.info("API key present for \(selectedProvider.rawValue, privacy: .public)")

        // 3. Get selected text
        let isTrusted = AccessibilityService.isTrusted
        debugLastStage = "Accessibility trusted: \(isTrusted)"
        log.info("Accessibility trusted: \(isTrusted)")

        var sourceText: String?

        if isTrusted {
            sourceText = accessibilityService.getSelectedText()
            debugLastStage = "AX read result: \(selectionState(sourceText))"
            log.info("AX selected text: \(sourceText ?? "<nil>")")
        }

        // Fallback: clipboard simulation
        if sourceText == nil || sourceText?.isEmpty == true {
            debugLastStage = "Trying clipboard fallback"
            log.info("AX failed or empty, trying clipboard fallback...")
            clipboardService.saveAndClear()
            clipboardService.simulateCopy()
            try? await Task.sleep(nanoseconds: Constants.copyWaitDelay)
            sourceText = clipboardService.readText()
            debugLastStage = "Clipboard read result: \(selectionState(sourceText))"
            log.info("Clipboard text: \(sourceText ?? "<nil>")")
        }

        guard let text = sourceText, !text.isEmpty else {
            debugLastStage = "Blocked: no selected text"
            log.error("No text captured from any method")
            lastError = TranslationError.noTextSelected.localizedDescription
            return
        }

        debugLastStage = "Text captured (\(text.count) chars)"
        log.info("Translating \(text.count) chars to \(self.settingsVM.settings.targetLanguage.rawValue) [\(self.settingsVM.settings.tone.rawValue)]")

        // 4. Translate
        isTranslating = true
        lastError = nil
        debugLastStage = "Calling translation provider"
        notifyAppDelegate { $0.showTranslatingIcon() }

        defer {
            isTranslating = false
            notifyAppDelegate { $0.restoreDefaultIcon() }
        }

        let settings = settingsVM.settings
        let provider: TranslationProvider
        switch selectedProvider {
        case .claude:
            provider = ClaudeProvider(apiKey: apiKey)
        case .openAI:
            provider = OpenAIProvider(apiKey: apiKey)
        case .gemini:
            provider = GeminiProvider(apiKey: apiKey)
        }
        let service = TranslationService(provider: provider)
        let customPrompt = settings.customTonePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = TranslationRequest(
            text: text,
            targetLanguage: settings.targetLanguage,
            tone: settings.tone,
            customTonePrompt: customPrompt.isEmpty ? nil : customPrompt
        )

        do {
            let response = try await service.translate(request, apiKey: apiKey)
            debugLastStage = "Translation received (\(response.translatedText.count) chars)"
            log.info("Translation received: \(response.translatedText.prefix(50))...")
            providerStatusByType[selectedProvider] = .ok(message: "OK")

            // 5. Output
            if settings.autoPaste {
                if isTrusted {
                    let axDidSet = accessibilityService.replaceSelectedText(with: response.translatedText)
                    if axDidSet {
                        try? await Task.sleep(nanoseconds: 120_000_000)
                        let afterAX = accessibilityService.getSelectedText()
                        let originalNormalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        let translatedNormalized = response.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
                        let afterNormalized = afterAX?.trimmingCharacters(in: .whitespacesAndNewlines)

                        if let afterNormalized, afterNormalized == originalNormalized {
                            debugLastStage = "AX replace reported success but selection unchanged"
                            log.warning("AX replace returned success but selected text is unchanged")
                        } else {
                            if afterNormalized == translatedNormalized {
                                debugLastStage = "Output: replaced via AX (verified)"
                            } else {
                                debugLastStage = "Output: replaced via AX (unverified)"
                            }
                            log.info("Replaced via AX")
                            notifyAppDelegate { $0.flashMenuBarIcon() }
                            return
                        }
                    } else {
                        debugLastStage = "AX replace failed"
                    }
                }

                debugLastStage = "Output: pasted via clipboard"
                log.info("AX replace failed, using clipboard paste")
                clipboardService.writeText(response.translatedText)
                clipboardService.simulatePaste()
                notifyAppDelegate { $0.flashMenuBarIcon() }

                Task {
                    try? await Task.sleep(nanoseconds: Constants.clipboardRestoreDelay)
                    clipboardService.restoreSaved()
                }
            } else {
                debugLastStage = "Output: copied to clipboard"
                clipboardService.writeText(response.translatedText)
                log.info("Copied to clipboard (auto-paste OFF)")
                notifyAppDelegate { $0.flashMenuBarIcon() }
            }
        } catch {
            if case let TranslationError.rateLimited(provider, retryAfter) = error {
                let retryText = retryAfter.map { "Retry in \($0)s." } ?? "Try again shortly."
                let message = "\(provider.rawValue) rate limited. \(retryText)"
                debugLastStage = "Error: \(provider.rawValue) 429"
                log.error("Translation rate limited for \(provider.rawValue, privacy: .public)")
                lastError = message
                providerStatusByType[provider] = .rateLimited(message: message, retryAfter: retryAfter)
                return
            }

            debugLastStage = "Error: \(error.localizedDescription)"
            log.error("Translation error: \(error.localizedDescription)")
            lastError = error.localizedDescription
            providerStatusByType[selectedProvider] = .error(message: error.localizedDescription)
        }
    }

    // MARK: - Private

    private func notifyAppDelegate(_ action: (AppDelegate) -> Void) {
        guard let delegate = NSApp.delegate as? AppDelegate else { return }
        action(delegate)
    }

    private func triggerTranslation(source: String) {
        debugHotkeyTriggerCount += 1
        debugLastTriggerSource = source
        debugLastTriggerAt = Date()
        debugLastStage = "Triggered from \(source)"
        log.info("Trigger received from \(source, privacy: .public)")
        Task { @MainActor in
            await self.performTranslation()
        }
    }

    private func selectionState(_ value: String?) -> String {
        guard let value else { return "nil" }
        return value.isEmpty ? "empty" : "non-empty"
    }

    private func appendDebugEvent(_ message: String) {
        let timestamp = Self.debugTimeFormatter.string(from: Date())
        let line = "[\(timestamp)] \(message)"
        debugEvents.insert(line, at: 0)
        if debugEvents.count > debugEventLimit {
            debugEvents.removeSubrange(debugEventLimit..<debugEvents.count)
        }
    }
}
