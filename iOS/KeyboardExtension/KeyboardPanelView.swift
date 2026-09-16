import ControlVCore
import SwiftUI
import UIKit

/// The keyboard's UI: a compact translation panel instead of a QWERTY layout.
/// The user types with their normal keyboard, then switches to this one to
/// translate what they wrote (or what they selected).
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
        VStack(spacing: 10) {
            header

            if !hasFullAccess {
                fullAccessPrompt
            } else {
                content
            }

            Spacer(minLength: 0)

            footer
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .tint(Brand.blue)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            BrandMark(size: 24, shadow: false)
            Text("Control-V").font(.footnote.weight(.semibold))
            Spacer(minLength: 4)
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
            settingMenu(title: settings.tone.rawValue, systemImage: "slider.horizontal.3") {
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
    }

    private func settingMenu<Content: View>(title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        Menu(content: content) {
            HStack(spacing: 4) {
                Image(systemName: systemImage).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Text(title).font(.caption.weight(.semibold)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassPill()
        }
        .menuOrder(.fixed)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle:
            VStack(spacing: 12) {
                Text(idleHint)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .padding(.top, 6)

                Button {
                    Task { await startTranslateFlow() }
                } label: {
                    Label("Translate & Replace", systemImage: "arrow.left.arrow.right")
                }
                .buttonStyle(PrimaryButtonStyle())
            }

        case .confirmTyped:
            VStack(spacing: 10) {
                Text("No selection found. Replace what you typed?")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)

                Text(detectedText)
                    .font(.callout)
                    .lineLimit(3)
                    .truncationMode(.head)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard(14)

                HStack(spacing: 8) {
                    Button("Cancel") { phase = .idle }
                        .buttonStyle(GlassButtonStyle())
                    Button {
                        Task { await translateTypedText() }
                    } label: {
                        Label("Translate & Replace", systemImage: "arrow.left.arrow.right")
                    }
                    .buttonStyle(PrimaryButtonStyle(compact: true))
                }
            }

        case .translating:
            statusBlock(symbol: nil, tint: Brand.blue, title: "Translating to \(settings.targetLanguage.rawValue)…", detail: nil, action: nil)

        case .done:
            statusBlock(symbol: "checkmark.circle.fill", tint: .green, title: "Replaced with the \(settings.targetLanguage.rawValue) translation", detail: nil, action: ("Translate more", { phase = .idle }))

        case .copiedFallback:
            statusBlock(symbol: "doc.on.clipboard.fill", tint: Brand.blue, title: "Copied instead", detail: "The text changed while translating, so nothing was replaced. Paste the translation from your clipboard.", action: ("OK", { phase = .idle }))

        case .error:
            statusBlock(symbol: "exclamationmark.triangle.fill", tint: .orange, title: "Couldn't translate", detail: errorMessage ?? "Something went wrong.", action: ("Try again", { phase = .idle }))
        }
    }

    private func statusBlock(symbol: String?, tint: Color, title: String, detail: String?, action: (String, () -> Void)?) -> some View {
        VStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol).font(.title2).foregroundStyle(tint)
            } else {
                ProgressView().tint(tint)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }
            if let action {
                Button(action.0, action: action.1)
                    .buttonStyle(GlassButtonStyle())
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var fullAccessPrompt: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.title2)
                .foregroundStyle(.orange)
            Text("Turn on Allow Full Access to translate")
                .font(.subheadline.weight(.semibold))
            Text("Settings → General → Keyboard → Keyboards → Control-V. Full Access only sends the text you choose to the translation service; keystrokes are never logged or stored.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var footer: some View {
        HStack {
            Button {
                actions.switchKeyboard()
            } label: {
                Image(systemName: "globe")
                    .font(.body.weight(.medium))
                    .frame(width: 44, height: 34)
                    .glassPill()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next keyboard")

            Spacer()

            if usedSelection {
                Label("Using selected text", systemImage: "text.cursor")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var idleHint: String {
        "Select text, or just finish typing, then tap the button. Your text is replaced with its \(settings.targetLanguage.rawValue) translation."
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
