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
    private(set) var debugLastLicenseLatencyMs: Int?
    private(set) var debugLastCaptureLatencyMs: Int?
    private(set) var debugLastBackendLatencyMs: Int?
    private(set) var debugLastOutputLatencyMs: Int?
    private(set) var debugLastTotalLatencyMs: Int?
    private(set) var debugLastModel = Constants.hostedModelName
    private(set) var debugLastStage = "Idle" {
        didSet { appendDebugEvent(debugLastStage) }
    }
    private(set) var debugEvents: [String] = []

    let settingsVM: SettingsViewModel
    weak var appDelegate: AppDelegate?

    private let accessibilityService = AccessibilityService()
    private let clipboardService = ClipboardService()
    private let hotkeyService = HotkeyService()
    private let licenseService: LicenseService
    private let deviceIdentityStore: DeviceIdentityStore
    private let debugEventLimit = 40
    private let gatewayWarmupInterval: TimeInterval = 15 * 60
    private var lastGatewayWarmupAt: Date?
    private var gatewayWarmupTask: Task<Void, Never>?

    private static let debugTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()

    init(
        licenseService: LicenseService,
        settingsViewModel: SettingsViewModel = SettingsViewModel(),
        deviceIdentityStore: DeviceIdentityStore = DeviceIdentityStore()
    ) {
        self.licenseService = licenseService
        self.settingsVM = settingsViewModel
        self.deviceIdentityStore = deviceIdentityStore
        setupHotkey()
        scheduleGatewayWarmupIfNeeded(reason: "startup")
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

        hotkeyService.register(
            carbonKeyCode: keyCode,
            carbonModifiers: modifiers,
            shortcutDisplay: settingsVM.shortcutDisplay
        )
        debugLastStage = "Hotkey registered (\(settingsVM.shortcutDisplay))"
        log.info("Hotkey registered: \(self.settingsVM.shortcutDisplay, privacy: .public)")
    }

    func debugPreviewTranslationIsland() {
        debugLastStage = "Debug: preview island"
        notifyAppDelegate { $0.debugShowTranslationIslandPreview() }
    }

    func performTranslation() async {
        guard !isTranslating else {
            debugLastStage = "Skipped: already translating"
            return
        }

        debugLastStage = "Flow started"
        let totalStartedAt = Date()
        resetDebugTimings()

        let licenseStartedAt = Date()
        await licenseService.refreshLicenseStatus(forceNetwork: false)
        debugLastLicenseLatencyMs = elapsedMs(since: licenseStartedAt)
        guard licenseService.state.canTranslate else {
            debugLastStage = "Blocked: license"
            lastError = TranslationError.trialExpired.localizedDescription
            notifyAppDelegate { $0.flashMenuBarIcon() }
            return
        }

        let isTrialMode = {
            if case .trial = licenseService.state { return true }
            return false
        }()

        guard let cloudProvider = makeCloudProvider(isTrialMode: isTrialMode) else {
            debugLastStage = "Blocked: backend not configured"
            lastError = TranslationError.backendNotConfigured.localizedDescription
            return
        }

        let captureStartedAt = Date()
        let capture = await captureSelectedText()
        debugLastCaptureLatencyMs = elapsedMs(since: captureStartedAt)
        guard let text = capture.text, !text.isEmpty else {
            debugLastStage = "Blocked: no selected text"
            lastError = TranslationError.noTextSelected.localizedDescription
            return
        }

        if isTrialMode {
            guard TrialTranslationService.isTextWithinLimit(text) else {
                let maxWords = TrialTranslationService.maxCharacters / 6
                debugLastStage = "Blocked: trial text too long"
                lastError = TranslationError.trialTextTooLong(maxWords: maxWords).localizedDescription
                return
            }
            guard TrialTranslationService.canTranslate() else {
                debugLastStage = "Blocked: trial quota exceeded"
                lastError = TranslationError.trialQuotaExceeded(remaining: 0).localizedDescription
                return
            }
        }

        let settings = settingsVM.settings
        let request = makeTranslationRequest(from: text, settings: settings)
        let prompt = PromptBuilder.buildSystemPrompt(
            targetLanguage: request.targetLanguage.rawValue,
            tone: request.tone,
            customTonePrompt: request.customTonePrompt
        )
        let startedAt = Date()
        let routing = resolveModelDecision(textLength: text.count, isTrialMode: isTrialMode)
        debugLastModel = routing.model

        isTranslating = true
        lastError = nil
        debugLastStage = "Calling ctrl+v Cloud"
        notifyAppDelegate { $0.showTranslatingIcon() }

        defer {
            isTranslating = false
            notifyAppDelegate { $0.restoreDefaultIcon() }
        }

        do {
            let backendStartedAt = Date()
            let translatedText = try await cloudProvider.translate(text: text, systemPrompt: prompt)
            debugLastBackendLatencyMs = elapsedMs(since: backendStartedAt)
            if isTrialMode {
                TrialTranslationService.recordTranslation()
            }

            let outputStartedAt = Date()
            try await writeTranslatedText(
                translatedText,
                originalText: text,
                autoPaste: settings.autoPaste,
                isTrusted: capture.isTrusted,
                usedClipboardCapture: capture.usedClipboardCapture
            )
            debugLastOutputLatencyMs = elapsedMs(since: outputStartedAt)
            debugLastTotalLatencyMs = elapsedMs(since: totalStartedAt)
            appendDebugEvent(
                "Timings license=\(debugLastLicenseLatencyMs ?? 0)ms capture=\(debugLastCaptureLatencyMs ?? 0)ms backend=\(debugLastBackendLatencyMs ?? 0)ms output=\(debugLastOutputLatencyMs ?? 0)ms total=\(debugLastTotalLatencyMs ?? 0)ms model=\(debugLastModel)"
            )

            let latencyMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            TelemetryService.trackTranslationCompleted(
                provider: .ctrlVCloud,
                targetLanguage: settings.targetLanguage,
                tone: settings.tone,
                method: outputMethod(autoPaste: settings.autoPaste, isTrusted: capture.isTrusted),
                textLength: text.count,
                model: routing.model,
                modelTier: routing.tier,
                latencyMs: latencyMs,
                progressivePasteUsed: false
            )
        } catch let error as TranslationError {
            handleTranslationError(error)
        } catch {
            debugLastStage = "Error: \(error.localizedDescription)"
            lastError = error.localizedDescription
            TelemetryService.trackTranslationFailed(provider: .ctrlVCloud, errorType: String(describing: error))
        }
    }

    private func setupHotkey() {
        hotkeyService.onTrigger = { [weak self] in
            self?.triggerTranslation(source: "hotkey")
        }
        refreshHotkeyRegistration()
    }

    private func makeCloudProvider(isTrialMode: Bool) -> CtrlVCloudProvider? {
        guard let endpoint = Constants.translationAPIURL else {
            return nil
        }

        let licenseKey = isTrialMode ? nil : licenseService.storedLicenseKey
        let instanceID = isTrialMode ? nil : licenseService.storedInstanceID

        return CtrlVCloudProvider(
            endpoint: endpoint,
            installID: deviceIdentityStore.currentInstallID(),
            licenseKey: licenseKey,
            licenseInstanceID: instanceID
        )
    }

    private func scheduleGatewayWarmupIfNeeded(reason: String) {
        guard gatewayWarmupTask == nil else { return }
        if let lastGatewayWarmupAt,
           Date().timeIntervalSince(lastGatewayWarmupAt) < gatewayWarmupInterval {
            return
        }

        let isTrialMode = {
            if case .trial = licenseService.state { return true }
            return false
        }()

        guard let cloudProvider = makeCloudProvider(isTrialMode: isTrialMode) else {
            return
        }

        let settings = settingsVM.settings
        let prompt = PromptBuilder.buildSystemPrompt(
            targetLanguage: settings.targetLanguage.rawValue,
            tone: settings.tone,
            customTonePrompt: normalizedCustomPrompt(settings.customTonePrompt)
        )

        gatewayWarmupTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            do {
                try await cloudProvider.warmup(systemPrompt: prompt)
                await MainActor.run {
                    self?.lastGatewayWarmupAt = Date()
                    self?.debugLastStage = "Warmup ready (\(reason))"
                    self?.gatewayWarmupTask = nil
                }
            } catch {
                await MainActor.run {
                    self?.appendDebugEvent("Warmup skipped: \(error.localizedDescription)")
                    self?.gatewayWarmupTask = nil
                }
            }
        }
    }

    private func captureSelectedText() async -> (text: String?, isTrusted: Bool, usedClipboardCapture: Bool) {
        let isTrusted = AccessibilityService.isTrusted
        debugLastStage = "Accessibility trusted: \(isTrusted)"

        var sourceText: String?
        var usedClipboardCapture = false

        if isTrusted {
            sourceText = accessibilityService.getSelectedText()
            debugLastStage = "AX read result: \(selectionState(sourceText))"
        }

        if sourceText == nil || sourceText?.isEmpty == true {
            debugLastStage = "Trying clipboard fallback"
            usedClipboardCapture = true
            clipboardService.saveAndClear()
            clipboardService.simulateCopy()
            try? await Task.sleep(nanoseconds: Constants.copyWaitDelay)
            sourceText = clipboardService.readText()
            debugLastStage = "Clipboard read result: \(selectionState(sourceText))"
        }

        return (sourceText, isTrusted, usedClipboardCapture)
    }

    private func makeTranslationRequest(from text: String, settings: AppSettings) -> TranslationRequest {
        return TranslationRequest(
            text: text,
            targetLanguage: settings.targetLanguage,
            tone: settings.tone,
            customTonePrompt: normalizedCustomPrompt(settings.customTonePrompt)
        )
    }

    private func normalizedCustomPrompt(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func resolveModelDecision(textLength: Int, isTrialMode: Bool) -> ModelRoutingDecision {
        ModelRouter.route(
            provider: .ctrlVCloud,
            textLength: textLength,
            isTrialMode: isTrialMode,
            forceFast: false
        )
    }

    private func writeTranslatedText(
        _ translatedText: String,
        originalText: String,
        autoPaste: Bool,
        isTrusted: Bool,
        usedClipboardCapture: Bool
    ) async throws {
        if !autoPaste {
            clipboardService.writeText(translatedText)
            debugLastStage = "Output: copied to clipboard"
            notifyAppDelegate { $0.flashMenuBarIcon() }
            return
        }

        if isTrusted, accessibilityService.replaceSelectedText(with: translatedText) {
            try? await Task.sleep(nanoseconds: Constants.axVerificationDelay)
            let current = accessibilityService.getSelectedText()?.trimmingCharacters(in: .whitespacesAndNewlines)
            let original = originalText.trimmingCharacters(in: .whitespacesAndNewlines)

            if current != original {
                debugLastStage = "Output: replaced via AX"
                restoreClipboardAfterAXIfNeeded(usedClipboardCapture: usedClipboardCapture)
                notifyAppDelegate { $0.flashMenuBarIcon() }
                return
            }
        }

        clipboardService.writeText(translatedText)
        clipboardService.simulatePaste()
        debugLastStage = "Output: pasted via clipboard"
        notifyAppDelegate { $0.flashMenuBarIcon() }

        Task {
            try? await Task.sleep(nanoseconds: Constants.clipboardRestoreDelay)
            clipboardService.restoreSaved()
        }
    }

    private func outputMethod(autoPaste: Bool, isTrusted: Bool) -> String {
        if !autoPaste {
            return "copy"
        }
        return isTrusted ? "AX" : "paste"
    }

    private func handleTranslationError(_ error: TranslationError) {
        switch error {
        case .rateLimited(_, let retryAfter):
            let retryText = retryAfter.map { "Retry in \($0)s." } ?? "Try again shortly."
            let message = "ctrl+v Cloud rate limited. \(retryText)"
            debugLastStage = "Error: 429"
            lastError = message
            TelemetryService.trackTranslationRateLimited(provider: .ctrlVCloud, retryAfter: retryAfter)
        default:
            debugLastStage = "Error: \(error.localizedDescription)"
            lastError = error.localizedDescription
            TelemetryService.trackTranslationFailed(provider: .ctrlVCloud, errorType: String(describing: error))
        }
    }

    private func restoreClipboardAfterAXIfNeeded(usedClipboardCapture: Bool) {
        guard usedClipboardCapture else { return }
        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            clipboardService.restoreSaved()
        }
    }

    private func notifyAppDelegate(_ action: (AppDelegate) -> Void) {
        guard let appDelegate else { return }
        action(appDelegate)
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

    private func resetDebugTimings() {
        debugLastLicenseLatencyMs = nil
        debugLastCaptureLatencyMs = nil
        debugLastBackendLatencyMs = nil
        debugLastOutputLatencyMs = nil
        debugLastTotalLatencyMs = nil
        debugLastModel = Constants.hostedModelName
    }

    private func elapsedMs(since start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }

    nonisolated static func shouldUseProgressivePaste(provider: ProviderType, autoPaste: Bool, isTrusted: Bool) -> Bool {
        false
    }
}
