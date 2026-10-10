import ControlVCore
import Foundation
import UIKit

/// Callbacks bridging the keyboard's keys to the text document proxy.
struct KeyboardActions {
    let readSelectedText: () -> String?
    let readTypedText: () -> String?
    let replaceSelectedText: (String) -> Void
    let replaceTypedText: (_ original: String, _ translation: String) -> Void
    let insertText: (String) -> Void
    let deleteBackward: () -> Void
    let contextBeforeInput: () -> String?
}

/// The translate action behind the Control-V key: reads what to translate,
/// calls the backend, replaces the text in place, and exposes a phase for
/// the status strip above the keys.
///
/// Safety model (defends against host-app quirks):
/// - Selection path: only replaces if the selection still matches after the
///   network await; otherwise falls back to copying the translation.
/// - Typed-text path: `replaceTypedText` refuses to delete text it did not
///   capture (hosts like WKWebView return nil from `selectedText` even when
///   text IS selected, and a blind deleteBackward would destroy it).
@MainActor
final class TranslateFlow: ObservableObject {
    enum Phase: Equatable {
        case idle
        case translating
        case done
        case copiedFallback
        case error
        /// Without Full Access: typos fixed on the device (`fixedCount`).
        case fixed
        /// A neutral note (`infoMessage`), e.g. nothing to fix.
        case info
        /// The trial ran out (`upgrade`): says where to subscribe. A keyboard
        /// may open nothing but Settings (App Review 4.4.1), so no link.
        case upgrade
    }

    @Published var phase: Phase = .idle
    @Published var errorMessage: String?
    @Published var infoMessage: String?
    @Published private(set) var fixedCount = 0
    @Published private(set) var upgrade: UpgradePrompt?
    @Published var settings = ExtensionBridge.loadSettings()
    /// Language and tone chips in the band above the keys (long press on V).
    @Published var showsOptions = false

    private(set) var detectedText = ""
    private(set) var translatedText = ""
    private(set) var usedSelection = false

    let hasFullAccess: Bool
    let actions: KeyboardActions

    init(hasFullAccess: Bool, actions: KeyboardActions) {
        self.hasFullAccess = hasFullAccess
        self.actions = actions
    }

    /// Fixed state for previews and snapshot tests.
    func applyPreview(phase: Phase, errorMessage: String? = nil, showsOptions: Bool = false, fixedCount: Int = 0,
                      upgrade: TranslationError? = nil) {
        self.phase = phase
        self.errorMessage = errorMessage
        self.infoMessage = errorMessage
        self.fixedCount = fixedCount
        self.showsOptions = showsOptions
        self.upgrade = upgrade.map(UpgradePrompt.init)
    }

    var isBusy: Bool { phase != .idle }

    func toggleOptions() {
        showsOptions.toggle()
    }

    func select(language: SupportedLanguage) {
        settings.targetLanguage = language
        ExtensionBridge.save(settings)
    }

    func select(tone: Tone) {
        settings.tone = tone
        ExtensionBridge.save(settings)
    }

    func dismissStatus() {
        phase = .idle
    }

    func translate() {
        Task { await startTranslateFlow() }
    }

    // MARK: - Flow

    private func startTranslateFlow() async {
        settings = ExtensionBridge.loadSettings()
        errorMessage = nil
        infoMessage = nil
        showsOptions = false

        // Without Full Access (no network) the key fixes typos on the device
        // instead, so it does something either way.
        let selection = actions.readSelectedText()
        if let selection, !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            detectedText = selection
            usedSelection = true
            if hasFullAccess { await translateSelection() } else { fixTyposOffline() }
            return
        }

        let typed = actions.readTypedText()
        if let typed, !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            detectedText = typed
            usedSelection = false
            if hasFullAccess { await translateTypedText() } else { fixTyposOffline() }
            return
        }

        if hasFullAccess {
            errorMessage = "Nothing to translate. Select text or type something first."
            phase = .error
        } else {
            infoMessage = "Type or select text, then tap V to fix typos. Translating needs Full Access."
            phase = .info
        }
    }

    /// iOS's spell checker, on the device: the one thing the key can do with
    /// no network. Replaces like a translation, so Undo works the same way.
    private func fixTyposOffline() {
        let preferred = [Locale.current.language.languageCode?.identifier, settings.targetLanguage.bcp47].compactMap { $0 }
        let result = OfflineSpelling.correct(detectedText, preferred: preferred)
        guard result.fixes > 0 else {
            infoMessage = "No typos found. Translating needs Full Access."
            phase = .info
            return
        }
        translatedText = result.text
        if usedSelection {
            actions.replaceSelectedText(result.text)
        } else {
            actions.replaceTypedText(detectedText, result.text)
        }
        fixedCount = result.fixes
        phase = .fixed
        Task {
            try? await Task.sleep(for: .seconds(3.5))
            if phase == .fixed { phase = .idle }
        }
    }

    private func translateSelection() async {
        phase = .translating
        guard let translation = await fetchTranslation(for: detectedText) else { return }
        translatedText = translation
        // TOCTOU guard: only replace if the selection is still exactly what
        // was translated; otherwise the user moved on.
        if actions.readSelectedText() == detectedText {
            actions.replaceSelectedText(translation)
            finishDone()
        } else {
            UIPasteboard.general.string = translation
            phase = .copiedFallback
        }
    }

    private func translateTypedText() async {
        phase = .translating
        guard let translation = await fetchTranslation(for: detectedText) else { return }
        translatedText = translation
        // TOCTOU guard: only delete if the text before the cursor still ends
        // with what was captured.
        if (actions.readTypedText() ?? "") == detectedText {
            actions.replaceTypedText(detectedText, translation)
            finishDone()
        } else {
            UIPasteboard.general.string = translation
            phase = .copiedFallback
        }
    }

    private func finishDone() {
        phase = .done
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if phase == .done { phase = .idle }
        }
    }

    /// Puts the original text back when the user says the replacement was wrong.
    func undoReplacement() {
        guard !translatedText.isEmpty, !detectedText.isEmpty else { phase = .idle; return }
        actions.replaceTypedText(translatedText, detectedText)
        phase = .idle
    }

    private func fetchTranslation(for text: String) async -> String? {
        guard let service = ExtensionBridge.makeTranslationService() else {
            errorMessage = "Translation service not configured."
            phase = .error
            return nil
        }
        let request = TranslationRequest(text: text, targetLanguage: settings.targetLanguage, tone: settings.tone, customTonePrompt: settings.customTonePrompt)
        do {
            return try await service.translate(request).translatedText
        } catch let error as TranslationError where error.requiresSubscription {
            upgrade = UpgradePrompt(error)
            phase = .upgrade
            return nil
        } catch {
            errorMessage = error.localizedDescription
            phase = .error
            return nil
        }
    }
}
