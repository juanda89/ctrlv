import ControlVCore
import SwiftUI
import UIKit

/// The Control-V keyboard: a normal QWERTY keyboard with one extra button.
///
/// The first version replaced the whole keyboard with a translation panel, so
/// using it meant switching keyboards for every translation and switching back
/// to type. Now the user can leave Control-V enabled as their keyboard and the
/// translate action is always one tap away, above the keys.
///
/// Safety model (defends against host-app quirks):
/// - Selection path: only replaces if the selection still matches after the
///   network await; otherwise falls back to copying the translation.
/// - Typed-text path: NEVER auto-replaces. Shows the captured text and asks
///   the user to confirm — because hosts like WKWebView return nil from
///   selectedText even when text IS selected, and blind deleteBackward would
///   destroy the wrong text.
struct KeyboardPanelView: View {
    let hasFullAccess: Bool
    let actions: KeyboardActions

    @State private var phase: Phase
    @State private var detectedText: String
    @State private var translatedText: String
    @State private var usedSelection: Bool
    @State private var errorMessage: String?
    @State private var settings = ExtensionBridge.loadSettings()

    enum Phase {
        case idle              // waiting for user to tap Translate
        case confirmTyped      // typed-text fallback: show capture, ask to confirm
        case translating
        case done              // translation inserted
        case copiedFallback    // document changed mid-flight; translation on clipboard
        case error
    }

    /// Fixed starting state for previews and snapshot tests. Production
    /// always starts idle.
    struct PreviewState {
        var phase: Phase = .idle
        var detectedText = ""
        var translatedText = ""
        var usedSelection = false
        var errorMessage: String? = nil
    }

    init(hasFullAccess: Bool, actions: KeyboardActions, preview: PreviewState? = nil) {
        self.hasFullAccess = hasFullAccess
        self.actions = actions
        let start = preview ?? PreviewState()
        _phase = State(initialValue: start.phase)
        _detectedText = State(initialValue: start.detectedText)
        _translatedText = State(initialValue: start.translatedText)
        _usedSelection = State(initialValue: start.usedSelection)
        _errorMessage = State(initialValue: start.errorMessage)
    }

    var body: some View {
        VStack(spacing: 8) {
            actionBar
                .frame(height: 46)
                .padding(.horizontal, 6)
            KeyboardLayoutView(actions: actions)
        }
        .padding(.top, 6)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
        .tint(Brand.blue)
    }

    // MARK: - Action bar

    @ViewBuilder
    private var actionBar: some View {
        if !hasFullAccess {
            statusBar(symbol: "lock.shield", tint: .orange,
                      text: "Turn on Allow Full Access in Settings to translate",
                      action: nil)
        } else {
            switch phase {
            case .idle:
                HStack(spacing: 8) {
                    Button { Task { await startTranslateFlow() } } label: {
                        Label("Translate", systemImage: "arrow.left.arrow.right")
                    }
                    .buttonStyle(PrimaryButtonStyle(compact: true))

                    settingMenu(title: settings.targetLanguage.rawValue, systemImage: "globe") {
                        ForEach(SupportedLanguage.allCases) { language in
                            Button {
                                settings.targetLanguage = language
                                ExtensionBridge.save(settings)
                            } label: {
                                if language == settings.targetLanguage { Label(language.rawValue, systemImage: "checkmark") } else { Text(language.rawValue) }
                            }
                        }
                    }
                    settingMenu(title: nil, systemImage: "slider.horizontal.3") {
                        ForEach(Tone.allCases) { tone in
                            Button {
                                settings.tone = tone
                                ExtensionBridge.save(settings)
                            } label: {
                                if tone == settings.tone { Label(tone.rawValue, systemImage: "checkmark") } else { Text(tone.rawValue) }
                            }
                        }
                    }
                }

            case .confirmTyped:
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Replace what you typed?").font(.caption.weight(.semibold))
                        Text(detectedText).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                    }
                    Spacer(minLength: 0)
                    Button("Cancel") { phase = .idle }
                        .buttonStyle(GlassButtonStyle())
                    Button { Task { await translateTypedText() } } label: { Text("Replace") }
                        .buttonStyle(PrimaryButtonStyle(compact: true))
                        .fixedSize()
                }

            case .translating:
                statusBar(symbol: nil, tint: Brand.blue, text: "Translating to \(settings.targetLanguage.rawValue)…", action: nil)

            case .done:
                statusBar(symbol: "checkmark.circle.fill", tint: .green,
                          text: "Replaced with the \(settings.targetLanguage.rawValue) translation",
                          action: ("Undo", undoReplacement))

            case .copiedFallback:
                statusBar(symbol: "doc.on.clipboard.fill", tint: Brand.blue,
                          text: "The text changed, so the translation was copied instead",
                          action: ("OK", { phase = .idle }))

            case .error:
                statusBar(symbol: "exclamationmark.triangle.fill", tint: .orange,
                          text: errorMessage ?? "Something went wrong.",
                          action: ("Try again", { phase = .idle }))
            }
        }
    }

    private func statusBar(symbol: String?, tint: Color, text: String, action: (String, () -> Void)?) -> some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol).font(.subheadline).foregroundStyle(tint)
            } else {
                ProgressView().controlSize(.small).tint(tint)
            }
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            if let action {
                Button(action.0, action: action.1)
                    .buttonStyle(GlassButtonStyle())
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .glassCard(12)
    }

    private func settingMenu<Content: View>(title: String?, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        Menu(content: content) {
            HStack(spacing: 4) {
                Image(systemName: systemImage).font(.caption.weight(.semibold))
                if let title { Text(title).font(.caption.weight(.semibold)).lineLimit(1) }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .glassPill()
        }
        .menuOrder(.fixed)
        .fixedSize()
    }

    // MARK: - Flow control

    /// Entry point from the idle button. Selection path proceeds directly;
    /// typed-text path requires explicit confirmation (see safety model above).
    private func startTranslateFlow() async {
        settings = ExtensionBridge.loadSettings()
        errorMessage = nil

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
            // Do NOT auto-replace: the host may have a selection it doesn't
            // expose to the proxy. Show what we captured and let the user decide.
            phase = .confirmTyped
            return
        }

        errorMessage = "Nothing to translate. Select text or type something first."
        phase = .error
    }

    private func translateSelection() async {
        phase = .translating

        guard let translation = await fetchTranslation(for: detectedText) else { return }
        translatedText = translation

        // TOCTOU guard: the network round-trip takes seconds. Only replace if
        // the selection is still exactly what we translated; otherwise the user
        // moved on and insertText would land in the wrong place.
        let selectionNow = actions.readSelectedText()
        if selectionNow == detectedText {
            actions.replaceSelectedText(translation)
            phase = .done
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
        // with what we captured. If the user typed more, moved the caret, or
        // switched fields during the await, deleting would destroy other text.
        let typedNow = actions.readTypedText() ?? ""
        if typedNow == detectedText {
            actions.replaceTypedText(detectedText, translation)
            phase = .done
        } else {
            UIPasteboard.general.string = translation
            phase = .copiedFallback
        }
    }

    /// Puts the original text back when the user says the replacement was wrong.
    private func undoReplacement() {
        guard !translatedText.isEmpty, !detectedText.isEmpty else { phase = .idle; return }
        actions.replaceTypedText(translatedText, detectedText)
        phase = .idle
    }

    /// Shared network call. Returns nil after setting the error phase.
    private func fetchTranslation(for text: String) async -> String? {
        guard let service = ExtensionBridge.makeTranslationService() else {
            errorMessage = "Translation service not configured."
            phase = .error
            return nil
        }

        let request = TranslationRequest(
            text: text,
            targetLanguage: settings.targetLanguage,
            tone: settings.tone,
            customTonePrompt: settings.customTonePrompt
        )

        do {
            let response = try await service.translate(request)
            return response.translatedText
        } catch {
            errorMessage = error.localizedDescription
            phase = .error
            return nil
        }
    }
}
