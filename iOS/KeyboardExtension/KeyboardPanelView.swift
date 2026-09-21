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

    /// The band above the keys. iOS draws a 16 pt lip above a third-party
    /// keyboard's view, so 35 pt here shows as the 51 pt the system keyboard
    /// reserves for its predictive bar: the keyboard is then exactly as tall
    /// as the system one (apps do not reflow when the user switches keyboards)
    /// and key previews of the top row have room to rise (an extension's
    /// window clips anything outside it). While translating, the status strip
    /// lives here instead of over the keys.
    static let bandHeight: CGFloat = 35
    /// Between the last row and the system's globe bar (measured: 3 pt).
    static let bottomPadding: CGFloat = 3

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
        VStack(spacing: 0) {
            ZStack {
                // Only while something is happening: at rest this is an
                // ordinary keyboard, with the Control-V key next to space.
                if isBusy {
                    statusBar
                        .padding(.horizontal, 6)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .frame(height: Self.bandHeight)
            KeyboardLayoutView(
                actions: actions,
                settings: $settings,
                onTranslate: { Task { await startTranslateFlow() } }
            )
        }
        .padding(.bottom, Self.bottomPadding)
        // Anchored to the bottom: while iOS animates the input view from the
        // previous keyboard's height to ours, top-aligned keys would sit high
        // up in the taller view for a frame and then drop into place.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .background(Color.clear)
        .tint(Brand.blue)
        .animation(.smooth(duration: 0.28), value: phaseID)
    }

    private var isBusy: Bool {
        if case .idle = phase { return false }
        return true
    }

    /// Drives the animation between states so translating → done cross-fades
    /// instead of snapping.
    private var phaseID: Int {
        switch phase {
        case .idle: return 0
        case .confirmTyped: return 1
        case .translating: return 2
        case .done: return 3
        case .copiedFallback: return 4
        case .error: return 5
        }
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
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
            }
            .task {
                try? await Task.sleep(for: .seconds(2.5))
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
        .frame(height: 31)
        .glassCard(10)
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
            // Straight to work: asking "replace what you typed?" on every tap
            // was friction for the common case. Undo covers the rare miss, and
            // translateTypedText still refuses to delete text it didn't capture.
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
