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
    }

    @Published var phase: Phase = .idle
    @Published var errorMessage: String?
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
    func applyPreview(phase: Phase, errorMessage: String? = nil, showsOptions: Bool = false) {
        self.phase = phase
        self.errorMessage = errorMessage
        self.showsOptions = showsOptions
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
        showsOptions = false

        guard hasFullAccess else {
            errorMessage = "Turn on Allow Full Access in Settings to translate."
            phase = .error
            return
        }

        let selection = actions.readSelectedText()
        if let selection, !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            detectedText = selection
            usedSelection = true
            await translateSelection()
            return
        }

        let typed = actions.readTypedText()
        if let typed, !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            detectedText = typed
            usedSelection = false
            await translateTypedText()
            return
        }

        errorMessage = "Nothing to translate. Select text or type something first."
        phase = .error
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
        } catch {
            errorMessage = error.localizedDescription
            phase = .error
            return nil
        }
    }
}
