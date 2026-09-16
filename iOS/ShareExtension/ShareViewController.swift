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

struct ShareResultView: View {
    let sourceText: String
    let onDone: () -> Void
    let onCopy: (String) -> Void

    /// Fixed state for previews and snapshot tests; production passes nil and
    /// runs the real translation on appear.
    enum Preview { case loading, done(String), failed(String) }
    private let preview: Preview?

    @State private var translated: String = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    private let settings = ExtensionBridge.loadSettings()

    init(sourceText: String, onDone: @escaping () -> Void, onCopy: @escaping (String) -> Void, preview: Preview? = nil) {
        self.sourceText = sourceText
        self.onDone = onDone
        self.onCopy = onCopy
        self.preview = preview
        switch preview {
        case .none, .loading: break
        case .done(let text): _translated = State(initialValue: text); _isLoading = State(initialValue: false)
        case .failed(let message): _errorMessage = State(initialValue: message); _isLoading = State(initialValue: false)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Label("Auto-detect", systemImage: "sparkles")
                            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .glassPill(interactive: false)
                        Image(systemName: "arrow.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                        Text(settings.targetLanguage.rawValue)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .glassPill(interactive: false)
                        Spacer()
                        Text(settings.tone.rawValue).font(.caption).foregroundStyle(.tertiary)
                    }

                    if isLoading {
                        HStack(spacing: 10) {
                            ProgressView().tint(Brand.blue)
                            Text("Translating…").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(28)
                        .glassCard(20)
                    } else if let errorMessage {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                            Button {
                                Task { isLoading = true; self.errorMessage = nil; await runTranslation() }
                            } label: { Label("Try again", systemImage: "arrow.clockwise") }
                            .buttonStyle(GlassButtonStyle())
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard(16)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionLabel(text: "Original")
                            Text(sourceText).font(.subheadline).foregroundStyle(.secondary).lineLimit(4)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard(18)

                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel(text: settings.targetLanguage.rawValue)
                            Text(translated).font(.title3).textSelection(.enabled)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard(20)

                        Button {
                            onCopy(translated)
                        } label: {
                            Label("Copy translation", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(translated.isEmpty)

                        Text("To replace text in place, use the Control-V keyboard.")
                            .font(.caption).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(18)
            }
            .background(AuroraBackground())
            .navigationTitle("Control-V")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel", action: onDone) }
            }
        }
        .tint(Brand.blue)
        .task { if preview == nil { await runTranslation() } }
    }

    private func runTranslation() async {
        defer { isLoading = false }

        // Usage limits (trial quota, character caps) are enforced server-side
        // by the translate Edge Function based on installID / session token.
        guard let service = ExtensionBridge.makeTranslationService() else {
            errorMessage = "Translation service not configured."
            return
        }

        let request = TranslationRequest(
            text: sourceText,
            targetLanguage: settings.targetLanguage,
            tone: settings.tone,
            customTonePrompt: settings.customTonePrompt
        )

        do {
            let response = try await service.translate(request)
            translated = response.translatedText
            ExtensionBridge.appendHistory(
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
