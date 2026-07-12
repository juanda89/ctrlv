import ControlVCore
import SwiftUI

/// The keyboard's UI: a compact translation panel instead of a QWERTY layout.
/// The user types with their normal keyboard, then switches to this one to
/// translate what they wrote (or what they selected).
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
        case idle          // waiting for user to tap Translate
        case translating
        case done          // translation inserted
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
                    Task { await translateAndReplace() }
                } label: {
                    Label("Translate & Replace", systemImage: "arrow.left.arrow.right")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)

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
            Text("Enable \"Allow Full Access\" for Control-V in Settings → General → Keyboard → Keyboards to translate.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
        .padding(.top, 16)
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

    // MARK: - Translation

    private func translateAndReplace() async {
        settings = KeyboardSettings.load()

        // Prefer explicit selection; fall back to everything typed before the cursor.
        let selection = actions.readSelectedText()
        let typed = actions.readTypedText()

        let source: String
        if let selection, !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            source = selection
            usedSelection = true
        } else if let typed, !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            source = typed
            usedSelection = false
        } else {
            errorMessage = "Nothing to translate. Select text or type something first."
            phase = .error
            return
        }

        detectedText = source
        phase = .translating

        guard let endpoint = Constants.translationAPIURL else {
            errorMessage = "Translation service not configured."
            phase = .error
            return
        }

        let provider = CtrlVCloudProvider(
            endpoint: endpoint,
            installID: KeyboardSettings.installID(),
            sessionToken: KeyboardSettings.sessionToken()
        )
        let service = TranslationService(provider: provider)
        let request = TranslationRequest(
            text: source,
            targetLanguage: settings.targetLanguage,
            tone: settings.tone,
            customTonePrompt: settings.customTonePrompt
        )

        do {
            let response = try await service.translate(request)
            translatedText = response.translatedText

            if usedSelection {
                actions.replaceSelectedText(translatedText)
            } else {
                actions.replaceTypedText(detectedText, translatedText)
            }
            phase = .done
        } catch {
            errorMessage = error.localizedDescription
            phase = .error
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
