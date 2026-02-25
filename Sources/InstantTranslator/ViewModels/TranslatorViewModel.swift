import AppKit
import Foundation
import os

private let log = Logger(subsystem: "com.instanttranslator.app", category: "translator")

@MainActor
@Observable
final class TranslatorViewModel {
    private(set) var isTranslating = false
    private(set) var lastError: String?
    private(set) var debugHotkeyTriggerCount = 0
    private(set) var debugLastTriggerSource = "none"
    private(set) var debugLastTriggerAt: Date?
    private(set) var debugLastStage = "Idle"

    let settingsVM = SettingsViewModel()

    private let accessibilityService = AccessibilityService()
    private let clipboardService = ClipboardService()
    private let hotkeyService = HotkeyService()
    private let licenseService: LicenseService

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
        let apiKey = settingsVM.apiKey
        guard !apiKey.isEmpty else {
            debugLastStage = "Blocked: missing API key"
            log.error("API key is empty")
            lastError = TranslationError.apiKeyMissing.localizedDescription
            return
        }
        debugLastStage = "API key OK"
        log.info("API key present (\(apiKey.prefix(10))...)")

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
        let provider = ClaudeProvider(apiKey: apiKey)
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

            // 5. Output
            if settings.autoPaste {
                if isTrusted,
                   accessibilityService.replaceSelectedText(with: response.translatedText) {
                    debugLastStage = "Output: replaced via AX"
                    log.info("Replaced via AX")
                    notifyAppDelegate { $0.flashMenuBarIcon() }
                    return
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
            debugLastStage = "Error: \(error.localizedDescription)"
            log.error("Translation error: \(error.localizedDescription)")
            lastError = error.localizedDescription
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
}
