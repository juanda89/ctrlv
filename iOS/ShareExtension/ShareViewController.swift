import ControlVCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Entry point for the Control-V Share Extension. iOS calls this when the
/// user taps the Control-V icon in the system share sheet. We extract the
/// selected text, run a translation, and present a compact result UI.
class ShareViewController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        Task {
            do {
                let text = try await extractSharedText()
                presentResult(for: text)
            } catch {
                presentError(error.localizedDescription)
            }
        }
    }

    // MARK: - Text extraction

    private func extractSharedText() async throws -> String {
        guard let item = (extensionContext?.inputItems.first as? NSExtensionItem),
              let attachment = item.attachments?.first(where: {
                  $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
                  || $0.hasItemConformingToTypeIdentifier(UTType.text.identifier)
                  || $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
              }) else {
            throw ShareError.noText
        }

        if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            return try await loadString(from: attachment, type: UTType.plainText.identifier)
        } else if attachment.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
            return try await loadString(from: attachment, type: UTType.text.identifier)
        } else {
            return try await loadString(from: attachment, type: UTType.url.identifier)
        }
    }

    private func loadString(from provider: NSItemProvider, type: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type, options: nil) { value, error in
                if let error {
                    continuation.resume(throwing: error); return
                }
                if let string = value as? String {
                    continuation.resume(returning: string)
                } else if let url = value as? URL {
                    continuation.resume(returning: url.absoluteString)
                } else if let data = value as? Data, let s = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: s)
                } else {
                    continuation.resume(throwing: ShareError.noText)
                }
            }
        }
    }

    // MARK: - UI

    private func presentResult(for text: String) {
        let host = UIHostingController(rootView: ShareResultView(
            sourceText: text,
            onDone: { [weak self] in self?.dismissExtension() },
            onCopy: { [weak self] translated in
                UIPasteboard.general.string = translated
                self?.dismissExtension()
            }
        ))
        host.modalPresentationStyle = .formSheet
        // Block swipe-to-dismiss: the extension MUST end via completeRequest,
        // otherwise the host app is left waiting on a stranded extension.
        host.isModalInPresentation = true
        present(host, animated: true)
    }

    private func presentError(_ message: String) {
        let alert = UIAlertController(title: "Control-V", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.dismissExtension()
        })
        present(alert, animated: true)
    }

    private func dismissExtension() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

private enum ShareError: LocalizedError {
    case noText
    var errorDescription: String? { "No text found in the share input." }
}

// MARK: - SwiftUI sheet shown inside the extension

private struct ShareResultView: View {
    let sourceText: String
    let onDone: () -> Void
    let onCopy: (String) -> Void

    @State private var translated: String = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isLoading {
                        HStack {
                            ProgressView()
                            Text("Translating…")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 32)
                        .frame(maxWidth: .infinity)
                    } else if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Original")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(sourceText)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Translation")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(translated)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Control-V")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onDone)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Copy") {
                        onCopy(translated)
                    }
                    .font(.body.weight(.semibold))
                    .disabled(translated.isEmpty || isLoading)
                }
            }
        }
        .task {
            await runTranslation()
        }
    }

    private func runTranslation() async {
        defer { isLoading = false }

        // Read user's preferred language + tone from App Group.
        // Usage limits (trial quota, character caps) are enforced server-side
        // by the translate Edge Function based on installID / session token.
        let settings = ShareExtensionSettings.load()

        guard let endpoint = Constants.translationAPIURL else {
            errorMessage = "Translation service not configured."
            return
        }

        let installID = ShareExtensionSettings.installID()
        let sessionToken = ShareExtensionSettings.sessionToken()

        let provider = CtrlVCloudProvider(
            endpoint: endpoint,
            installID: installID,
            sessionToken: sessionToken
        )
        let service = TranslationService(provider: provider)
        let request = TranslationRequest(
            text: sourceText,
            targetLanguage: settings.targetLanguage,
            tone: settings.tone,
            customTonePrompt: settings.customTonePrompt
        )

        do {
            let response = try await service.translate(request)
            translated = response.translatedText
            ShareExtensionHistory.append(
                source: sourceText,
                translated: translated,
                language: settings.targetLanguage,
                tone: settings.tone
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - App Group helpers (mirror of main app's stores)

private struct ShareSettingsRecord: Codable {
    var targetLanguage: SupportedLanguage = .english
    var tone: Tone = .original
    var customTonePrompt: String = ""
}

private enum ShareExtensionSettings {
    private static let appGroup = "group.info.controlv.shared"
    private static let settingsKey = "iOSAppSettings"
    private static let installIDKey = "ctrlvInstallID"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    static func load() -> ShareSettingsRecord {
        guard let data = defaults.data(forKey: settingsKey),
              let decoded = try? JSONDecoder().decode(ShareSettingsRecord.self, from: data) else {
            return ShareSettingsRecord()
        }
        return decoded
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
        // Read the encrypted account.enc from App Group container.
        // For simplicity in v1 the session token is stored as a separate key
        // in the App Group defaults by the main app on sign-in.
        defaults.string(forKey: "iOSSessionToken")
    }
}

private enum ShareExtensionHistory {
    private static let appGroup = "group.info.controlv.shared"
    private static let key = "iOSHistory"
    private static let maxEntries = 50

    private struct Entry: Codable {
        let id: UUID
        let source: String
        let translated: String
        let language: SupportedLanguage
        let tone: Tone
        let timestamp: Date
    }

    static func append(source: String, translated: String, language: SupportedLanguage, tone: Tone) {
        let defaults = UserDefaults(suiteName: appGroup) ?? .standard
        var entries = (defaults.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([Entry].self, from: $0) }) ?? []
        entries.insert(
            Entry(
                id: UUID(),
                source: source,
                translated: translated,
                language: language,
                tone: tone,
                timestamp: Date()
            ),
            at: 0
        )
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: key)
        }
    }
}
