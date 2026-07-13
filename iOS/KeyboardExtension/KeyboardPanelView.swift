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

    @State private var phase: Phase = .idle
    @State private var detectedText: String = ""
    @State private var translatedText: String = ""
    @State private var usedSelection = false
    @State private var errorMessage: String?
    @State private var settings = KeyboardSettings.load()

    enum Phase {
        case idle              // waiting for user to tap Translate
        case confirmTyped      // typed-text fallback: show capture, ask to confirm
        case translating
        case done              // translation inserted
        case copiedFallback    // document changed mid-flight; translation on clipboard
        case error
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
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground).opacity(0.01))
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "text.bubble.fill")
                    .font(.footnote)
                    .foregroundStyle(.tint)
                Text("Control-V")
                    .font(.footnote.weight(.semibold))
            }

            Spacer()

            Text("→ \(settings.targetLanguage.rawValue)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle:
            VStack(spacing: 12) {
                Text(idleHint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                Button {
                    Task { await startTranslateFlow() }
                } label: {
                    Label("Translate & Replace", systemImage: "arrow.left.arrow.right")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)

        case .confirmTyped:
            VStack(spacing: 10) {
                Text("No selection detected. Replace this typed text?")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)

                Text(detectedText)
                    .font(.callout)
                    .lineLimit(3)
                    .truncationMode(.head)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 10) {
                    Button("Cancel") {
                        phase = .idle
                    }
                    .buttonStyle(.bordered)

                    Button("Translate & Replace") {
                        Task { await translateTypedText() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

        case .translating:
            VStack(spacing: 10) {
                ProgressView()
                Text("Translating…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 20)

        case .done:
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.green)
                Text("Replaced with translation")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Translate more") {
                    phase = .idle
                }
                .font(.footnote)
            }
            .padding(.top, 12)

        case .copiedFallback:
            VStack(spacing: 10) {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("The text changed while translating, so nothing was replaced. The translation is on your clipboard — paste it where you need it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                Button("OK") {
                    phase = .idle
                }
                .font(.footnote)
            }
            .padding(.top, 8)

        case .error:
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text(errorMessage ?? "Something went wrong")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                Button("Try again") {
                    phase = .idle
                }
                .font(.footnote)
            }
            .padding(.top, 12)
        }
    }

    private var fullAccessPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.title2)
                .foregroundStyle(.orange)
            Text("To translate, enable \"Allow Full Access\" in Settings → General → Keyboard → Keyboards → Control-V.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            Text("Full Access is used only to send the text you choose to translate to the Control-V translation service. Keystrokes are never logged and nothing you type is stored.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
        .padding(.top, 12)
    }

    private var footer: some View {
        HStack {
            Button {
                actions.switchKeyboard()
            } label: {
                Image(systemName: "globe")
                    .font(.title3)
                    .frame(width: 44, height: 36)
                    .background(Color(.secondarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            Spacer()

            Text(usedSelection ? "Using selected text" : "")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var idleHint: String {
        "Select text — or just finish typing — then tap the button. The text is replaced with its \(settings.targetLanguage.rawValue) translation."
    }

    // MARK: - Flow control

    /// Entry point from the idle button. Selection path proceeds directly;
    /// typed-text path requires explicit confirmation (see safety model above).
    private func startTranslateFlow() async {
        settings = KeyboardSettings.load()
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
        guard let endpoint = Constants.translationAPIURL else {
            errorMessage = "Translation service not configured."
            phase = .error
            return nil
        }

        let provider = CtrlVCloudProvider(
            endpoint: endpoint,
            installID: KeyboardSettings.installID(),
            sessionToken: KeyboardSettings.sessionToken()
        )
        let service = TranslationService(provider: provider)
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

// MARK: - App Group bridge (same data the main app + Share Extension use)

struct KeyboardSettings {
    var targetLanguage: SupportedLanguage = .english
    var tone: Tone = .original
    var customTonePrompt: String = ""

    private static let appGroup = "group.info.controlv.shared"
    private static let settingsKey = "iOSAppSettings"
    private static let installIDKey = "ctrlvInstallID"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    static func load() -> KeyboardSettings {
        guard let data = defaults.data(forKey: settingsKey),
              let decoded = try? JSONDecoder().decode(Stored.self, from: data) else {
            return KeyboardSettings()
        }
        return KeyboardSettings(
            targetLanguage: decoded.targetLanguage,
            tone: decoded.tone,
            customTonePrompt: decoded.customTonePrompt
        )
    }

    static func installID() -> String {
        if let existing = defaults.string(forKey: installIDKey), !existing.isEmpty {
            return existing
        }
        let new = UUID().uuidString.lowercased()
        defaults.set(new, forKey: installIDKey)
        return new
    }

    static func sessionToken() -> String? {
        defaults.string(forKey: "iOSSessionToken")
    }

    private struct Stored: Codable {
        var targetLanguage: SupportedLanguage
        var tone: Tone
        var customTonePrompt: String
    }
}
