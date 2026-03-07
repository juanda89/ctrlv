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

private struct TranslationRunResult {
    let translatedText: String
    let progressivePasteUsed: Bool
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

    let settingsVM: SettingsViewModel
    weak var appDelegate: AppDelegate?

    private let accessibilityService = AccessibilityService()
    private let clipboardService = ClipboardService()
    private let hotkeyService = HotkeyService()
    private let licenseService: LicenseService
    private var providersForcedToFast: Set<ProviderType> = []
    private let debugEventLimit = 40
    private static let debugTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()

    init(
        licenseService: LicenseService,
        settingsViewModel: SettingsViewModel = SettingsViewModel()
    ) {
        self.licenseService = licenseService
        self.settingsVM = settingsViewModel
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

    func setDebugProviderRuntimeStatus(_ status: ProviderRuntimeStatus, for provider: ProviderType) {
        providerStatusByType[provider] = status
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

        // 2. Determine provider + API key (trial mode uses bundled Gemini key)
        let selectedProvider = settingsVM.settings.selectedProvider
        let userApiKey = settingsVM.apiKey(for: selectedProvider)
        let isTrialMode: Bool
        let apiKey: String
        let effectiveProvider: ProviderType

        if !userApiKey.isEmpty {
            // User has their own key — use it directly, no trial limits
            isTrialMode = false
            apiKey = userApiKey
            effectiveProvider = selectedProvider
        } else if case .trial = licenseService.state {
            // Trial user without own key — use bundled Gemini
            isTrialMode = true
            apiKey = BundledTrialKey.geminiKey()
            effectiveProvider = .gemini
        } else {
            debugLastStage = "Blocked: missing API key"
            log.error("API key is empty")
            lastError = TranslationError.apiKeyMissing.localizedDescription
            providerStatusByType[selectedProvider] = .error(message: TranslationError.apiKeyMissing.localizedDescription)
            return
        }
        debugLastStage = isTrialMode ? "Trial mode (bundled Gemini)" : "API key OK"
        log.info("Provider: \(effectiveProvider.rawValue, privacy: .public), trial: \(isTrialMode)")

        // 3. Get selected text
        let isTrusted = AccessibilityService.isTrusted
        debugLastStage = "Accessibility trusted: \(isTrusted)"
        log.info("Accessibility trusted: \(isTrusted)")

        var sourceText: String?
        var didUseClipboardCapture = false

        if isTrusted {
            sourceText = accessibilityService.getSelectedText()
            debugLastStage = "AX read result: \(selectionState(sourceText))"
            log.info("AX selected text: \(sourceText ?? "<nil>")")
        }

        // Fallback: clipboard simulation
        if sourceText == nil || sourceText?.isEmpty == true {
            debugLastStage = "Trying clipboard fallback"
            log.info("AX failed or empty, trying clipboard fallback...")
            didUseClipboardCapture = true
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

        // Trial quota checks
        if isTrialMode {
            guard TrialTranslationService.isTextWithinLimit(text) else {
                let maxWords = TrialTranslationService.maxCharacters / 6
                debugLastStage = "Blocked: trial text too long"
                log.error("Trial text exceeds limit: \(text.count) chars")
                lastError = TranslationError.trialTextTooLong(maxWords: maxWords).localizedDescription
                return
            }
            guard TrialTranslationService.canTranslate() else {
                debugLastStage = "Blocked: trial quota exceeded"
                log.error("Trial daily quota exceeded")
                lastError = TranslationError.trialQuotaExceeded(remaining: 0).localizedDescription
                return
            }
        }

        let settings = settingsVM.settings
        let customPrompt = settings.customTonePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = TranslationRequest(
            text: text,
            targetLanguage: settings.targetLanguage,
            tone: settings.tone,
            customTonePrompt: customPrompt.isEmpty ? nil : customPrompt
        )
        let systemPrompt = PromptBuilder.buildSystemPrompt(
            targetLanguage: request.targetLanguage.rawValue,
            tone: request.tone,
            customTonePrompt: request.customTonePrompt
        )
        let translationStartedAt = Date()
        var modelDecision = resolveModelDecision(
            provider: effectiveProvider,
            textLength: text.count,
            isTrialMode: isTrialMode
        )

        do {
            let runResult: TranslationRunResult
            do {
                runResult = try await runTranslationAttempt(
                    providerType: effectiveProvider,
                    decision: modelDecision,
                    apiKey: apiKey,
                    text: text,
                    systemPrompt: systemPrompt,
                    allowProgressivePaste: Self.shouldUseProgressivePaste(
                        provider: effectiveProvider,
                        autoPaste: settings.autoPaste,
                        isTrusted: isTrusted
                    )
                )
            } catch {
                if modelDecision.tier == .robust,
                   shouldFallbackToFastModel(after: error, decision: modelDecision, isTrialMode: isTrialMode) {
                    providersForcedToFast.insert(effectiveProvider)
                    modelDecision = ModelRouter.route(
                        provider: effectiveProvider,
                        textLength: text.count,
                        isTrialMode: isTrialMode,
                        forceFast: true
                    )
                    debugLastStage = "Retrying with fast model (\(modelDecision.model))"
                    runResult = try await runTranslationAttempt(
                        providerType: effectiveProvider,
                        decision: modelDecision,
                        apiKey: apiKey,
                        text: text,
                        systemPrompt: systemPrompt,
                        allowProgressivePaste: Self.shouldUseProgressivePaste(
                            provider: effectiveProvider,
                            autoPaste: settings.autoPaste,
                            isTrusted: isTrusted
                        )
                    )
                } else {
                    throw error
                }
            }

            let translatedText = runResult.translatedText
            debugLastStage = "Translation received (\(translatedText.count) chars)"
            log.info("Translation received: \(translatedText.prefix(50))...")
            providerStatusByType[effectiveProvider] = .ok(message: "OK")

            if isTrialMode {
                TrialTranslationService.recordTranslation()
            }

            // 5. Output
            var outputMethod = "clipboard"
            if settings.autoPaste {
                if runResult.progressivePasteUsed {
                    outputMethod = "AX-stream"
                    debugLastStage = "Output: replaced progressively via AX"
                    restoreClipboardAfterAXIfNeeded(usedClipboardCapture: didUseClipboardCapture)
                    notifyAppDelegate { $0.flashMenuBarIcon() }
                } else if isTrusted {
                    let axDidSet = accessibilityService.replaceSelectedText(with: translatedText)
                    if axDidSet {
                        try? await Task.sleep(nanoseconds: 120_000_000)
                        let afterAX = accessibilityService.getSelectedText()
                        let originalNormalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        let translatedNormalized = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
                        let afterNormalized = afterAX?.trimmingCharacters(in: .whitespacesAndNewlines)

                        if let afterNormalized, afterNormalized == originalNormalized {
                            debugLastStage = "AX replace reported success but selection unchanged"
                            log.warning("AX replace returned success but selected text is unchanged")
                        } else {
                            outputMethod = "AX"
                            if afterNormalized == translatedNormalized {
                                debugLastStage = "Output: replaced via AX (verified)"
                            } else {
                                debugLastStage = "Output: replaced via AX (unverified)"
                            }
                            log.info("Replaced via AX")
                            restoreClipboardAfterAXIfNeeded(usedClipboardCapture: didUseClipboardCapture)
                            notifyAppDelegate { $0.flashMenuBarIcon() }
                        }
                    } else {
                        debugLastStage = "AX replace failed"
                    }
                }

                if outputMethod != "AX" && outputMethod != "AX-stream" {
                    outputMethod = "paste"
                    debugLastStage = "Output: pasted via clipboard"
                    log.info("AX replace failed, using clipboard paste")
                    clipboardService.writeText(translatedText)
                    clipboardService.simulatePaste()
                    notifyAppDelegate { $0.flashMenuBarIcon() }

                    Task {
                        try? await Task.sleep(nanoseconds: Constants.clipboardRestoreDelay)
                        clipboardService.restoreSaved()
                    }
                }
            } else {
                outputMethod = "copy"
                debugLastStage = "Output: copied to clipboard"
                clipboardService.writeText(translatedText)
                log.info("Copied to clipboard (auto-paste OFF)")
                notifyAppDelegate { $0.flashMenuBarIcon() }
            }

            let latencyMs = Int(Date().timeIntervalSince(translationStartedAt) * 1000)
            TelemetryService.trackTranslationCompleted(
                provider: effectiveProvider, targetLanguage: settings.targetLanguage,
                tone: settings.tone, method: outputMethod, textLength: text.count,
                model: modelDecision.model, modelTier: modelDecision.tier, latencyMs: latencyMs,
                progressivePasteUsed: runResult.progressivePasteUsed
            )
        } catch {
            if case let TranslationError.rateLimited(provider, retryAfter) = error {
                let retryText = retryAfter.map { "Retry in \($0)s." } ?? "Try again shortly."
                let message = "\(provider.rawValue) rate limited. \(retryText)"
                debugLastStage = "Error: \(provider.rawValue) 429"
                log.error("Translation rate limited for \(provider.rawValue, privacy: .public)")
                lastError = message
                providerStatusByType[provider] = .rateLimited(message: message, retryAfter: retryAfter)
                TelemetryService.trackTranslationRateLimited(provider: provider, retryAfter: retryAfter)
                return
            }

            debugLastStage = "Error: \(error.localizedDescription)"
            log.error("Translation error: \(error.localizedDescription)")
            lastError = error.localizedDescription
            providerStatusByType[effectiveProvider] = .error(message: error.localizedDescription)
            TelemetryService.trackTranslationFailed(provider: effectiveProvider, errorType: String(describing: error))
        }
    }

    // MARK: - Private

    private func notifyAppDelegate(_ action: (AppDelegate) -> Void) {
        guard let appDelegate else {
            log.warning("appDelegate is nil, skipping UI feedback")
            return
        }
        action(appDelegate)
    }

    nonisolated static func shouldUseProgressivePaste(provider: ProviderType, autoPaste: Bool, isTrusted: Bool) -> Bool {
        provider == .openAI && autoPaste && isTrusted
    }

    private func resolveModelDecision(provider: ProviderType, textLength: Int, isTrialMode: Bool) -> ModelRoutingDecision {
        let forceFast = !isTrialMode && providersForcedToFast.contains(provider)
        return ModelRouter.route(
            provider: provider,
            textLength: textLength,
            isTrialMode: isTrialMode,
            forceFast: forceFast
        )
    }

    private func makeProvider(providerType: ProviderType, apiKey: String, model: String) -> TranslationProvider {
        switch providerType {
        case .claude:
            return ClaudeProvider(apiKey: apiKey, model: model)
        case .openAI:
            return OpenAIProvider(apiKey: apiKey, model: model)
        case .gemini:
            return GeminiProvider(apiKey: apiKey, model: model)
        }
    }

    private func shouldFallbackToFastModel(
        after error: Error,
        decision: ModelRoutingDecision,
        isTrialMode: Bool
    ) -> Bool {
        guard !isTrialMode, decision.tier == .robust else { return false }
        guard case let TranslationError.apiError(statusCode, message) = error else { return false }
        guard statusCode == 400 || statusCode == 404 else { return false }
        if statusCode == 404 { return true }
        let lower = message.lowercased()
        return lower.contains("model")
            || lower.contains("not found")
            || lower.contains("does not exist")
            || lower.contains("unsupported")
    }

    private func runTranslationAttempt(
        providerType: ProviderType,
        decision: ModelRoutingDecision,
        apiKey: String,
        text: String,
        systemPrompt: String,
        allowProgressivePaste: Bool
    ) async throws -> TranslationRunResult {
        let provider = makeProvider(providerType: providerType, apiKey: apiKey, model: decision.model)
        let shouldStream = allowProgressivePaste && providerType == .openAI

        if shouldStream, let streamProvider = provider as? any StreamingTranslationProvider {
            guard let session = accessibilityService.beginProgressiveInsertionSession() else {
                TelemetryService.trackProgressivePasteFailed(
                    provider: providerType,
                    model: decision.model,
                    reason: .axInitFailed
                )
                let translated = try await provider.translate(text: text, systemPrompt: systemPrompt)
                return TranslationRunResult(translatedText: translated, progressivePasteUsed: false)
            }

            do {
                return try await runProgressiveStreaming(
                    streamProvider: streamProvider,
                    session: session,
                    providerType: providerType,
                    model: decision.model,
                    text: text,
                    systemPrompt: systemPrompt
                )
            } catch {
                TelemetryService.trackProgressivePasteFailed(
                    provider: providerType,
                    model: decision.model,
                    reason: .streamFailed
                )
                let translated = try await provider.translate(text: text, systemPrompt: systemPrompt)
                return TranslationRunResult(translatedText: translated, progressivePasteUsed: false)
            }
        }

        let translated = try await provider.translate(text: text, systemPrompt: systemPrompt)
        return TranslationRunResult(translatedText: translated, progressivePasteUsed: false)
    }

    private func runProgressiveStreaming(
        streamProvider: any StreamingTranslationProvider,
        session: ProgressiveInsertionSession,
        providerType: ProviderType,
        model: String,
        text: String,
        systemPrompt: String
    ) async throws -> TranslationRunResult {
        var streamText = ""
        var assembler = WordFlushAssembler(forceFlushInterval: 0.12)
        var progressiveFailure: ProgressiveInsertionFailureReason?

        for try await chunk in streamProvider.translateStream(text: text, systemPrompt: systemPrompt) {
            streamText += chunk

            guard progressiveFailure == nil else { continue }
            if let partial = assembler.append(chunk), let reason = session.apply(text: partial) {
                progressiveFailure = reason
                TelemetryService.trackProgressivePasteFailed(
                    provider: providerType,
                    model: model,
                    reason: reason
                )
            }
        }

        if progressiveFailure == nil,
           let finalPartial = assembler.forceFlush(),
           let reason = session.apply(text: finalPartial) {
            progressiveFailure = reason
            TelemetryService.trackProgressivePasteFailed(
                provider: providerType,
                model: model,
                reason: reason
            )
        }

        return TranslationRunResult(
            translatedText: streamText.trimmingCharacters(in: .whitespacesAndNewlines),
            progressivePasteUsed: progressiveFailure == nil
        )
    }

    private func restoreClipboardAfterAXIfNeeded(usedClipboardCapture: Bool) {
        guard usedClipboardCapture else { return }
        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            clipboardService.restoreSaved()
        }
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
