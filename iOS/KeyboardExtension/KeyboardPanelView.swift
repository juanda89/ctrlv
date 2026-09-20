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
        ZStack(alignment: .top) {
            KeyboardLayoutView(
                actions: actions,
                settings: $settings,
                onTranslate: { Task { await startTranslateFlow() } }
            )

            // Only while something is happening: at rest this is an ordinary
            // keyboard, with the Control-V key next to space.
            if isBusy {
                statusBar
                    .padding(.horizontal, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.top, 5)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
        .tint(Brand.blue)
        .animation(.snappy(duration: 0.2), value: isBusy)
    }

    private var isBusy: Bool {
        if case .idle = phase { return false }
        return true
    }

    // MARK: - Transient status

    @ViewBuilder
    private var statusBar: some View {
        switch phase {
        case .idle:
            EmptyView()

        case .confirmTyped:
            statusStrip(symbol: "text.cursor", tint: Brand.blue, text: "Replace what you typed?") {
                HStack(spacing: 6) {
                    Button("Cancel") { phase = .idle }
                        .buttonStyle(GlassButtonStyle())
                    Button("Replace") { Task { await translateTypedText() } }
                        .buttonStyle(PrimaryButtonStyle(compact: true))
                        .fixedSize()
                }
            }

        case .translating:
            statusStrip(symbol: nil, tint: Brand.blue, text: "Translating to \(settings.targetLanguage.rawValue)…") { EmptyView() }

        case .done:
            statusStrip(symbol: "checkmark.circle.fill", tint: .green, text: "Replaced") {
                Button("Undo") { undoReplacement() }
                    .buttonStyle(GlassButtonStyle())
            }
            .task {
                try? await Task.sleep(for: .seconds(2))
                if case .done = phase { phase = .idle }
            }

        case .copiedFallback:
            statusStrip(symbol: "doc.on.clipboard.fill", tint: Brand.blue, text: "Text changed, so it was copied") {
                Button("OK") { phase = .idle }
                    .buttonStyle(GlassButtonStyle())
            }

        case .error:
            statusStrip(symbol: "exclamationmark.triangle.fill", tint: .orange, text: errorMessage ?? "Something went wrong.") {
                Button("OK") { phase = .idle }
                    .buttonStyle(GlassButtonStyle())
            }
        }
    }

    private func statusStrip<Trailing: View>(symbol: String?, tint: Color, text: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol).font(.subheadline).foregroundStyle(tint)
            } else {
                ProgressView().controlSize(.small).tint(tint)
            }
            Text(text)
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .glassCard(12)
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }

    // MARK: - Flow control

    /// Entry point from the idle button. Selection path proceeds directly;
    /// typed-text path requires explicit confirmation (see safety model above).
    private func startTranslateFlow() async {
        settings = ExtensionBridge.loadSettings()
        errorMessage = nil

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
