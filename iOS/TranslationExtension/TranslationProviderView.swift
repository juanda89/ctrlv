import ControlVCore
import SwiftUI
import TranslationUIProvider

/// Content of the system translation sheet. Translates the selection as soon
/// as it appears; "Replace" hands the result back to the host app.
struct TranslationProviderView: View {
    let context: any TranslationUIProviderContext

    /// Fixed state for previews and snapshot tests; production passes nil.
    enum Preview { case translating, done(String), failed(String) }
    private let preview: Preview?

    @State private var settings = ExtensionBridge.loadSettings()
    @State private var phase: Phase = .translating
    @State private var translated = ""
    @State private var errorMessage: String?
    @State private var showCopied = false

    enum Phase { case translating, done, failed }

    init(context: any TranslationUIProviderContext, preview: Preview? = nil) {
        self.context = context
        self.preview = preview
        switch preview {
        case .none, .translating: break
        case .done(let text): _phase = State(initialValue: .done); _translated = State(initialValue: text)
        case .failed(let message): _phase = State(initialValue: .failed); _errorMessage = State(initialValue: message)
        }
    }

    private var sourceText: String {
        context.inputText.map { String($0.characters) } ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            sourceCard
            content
            if phase == .done { actions }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AuroraBackground())
        .tint(Brand.blue)
        .toast("Copied", isPresented: $showCopied)
        .task {
            if preview == nil {
                // Only reachable when Control-V is the default translation app.
                SetupState.markTranslationProviderActive()
                await translate()
            }
        }
    }

    // MARK: - Sections

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
                        Task { await translate() }
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
                        Task { await translate() }
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

    private var sourceCard: some View {
        Text(sourceText)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(3)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(16)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .translating:
            HStack(spacing: 10) {
                ProgressView().tint(Brand.blue)
                Text("Translating to \(settings.targetLanguage.rawValue)…").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(22)
            .glassCard(18)

        case .failed:
            VStack(alignment: .leading, spacing: 10) {
                Label(errorMessage ?? "Something went wrong.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button { Task { await translate() } } label: { Label("Try again", systemImage: "arrow.clockwise") }
                        .buttonStyle(GlassButtonStyle())
                    Spacer()
                    Button("Close") { context.finish(translation: nil) }
                        .buttonStyle(GlassButtonStyle())
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(18)

        case .done:
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: settings.targetLanguage.rawValue)
                Text(translated).font(.title3).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(18)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if context.allowsReplacement {
                Button { context.finish(translation: AttributedString(translated)) } label: {
                    Label("Replace", systemImage: "arrow.left.arrow.right")
                }
                .buttonStyle(PrimaryButtonStyle(compact: true))
                Button { copy() } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .buttonStyle(GlassButtonStyle())
            } else {
                Button { copy() } label: { Label("Copy translation", systemImage: "doc.on.doc") }
                    .buttonStyle(PrimaryButtonStyle(compact: true))
            }
            Spacer(minLength: 0)
            Button("Done") { context.finish(translation: nil) }
                .buttonStyle(GlassButtonStyle())
        }
    }

    // MARK: - Actions

    private func copy() {
        UIPasteboard.general.string = translated
        withAnimation { showCopied = true }
    }

    private func translate() async {
        phase = .translating
        errorMessage = nil
        let source = sourceText
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Nothing to translate."
            phase = .failed
            return
        }
        guard let service = ExtensionBridge.makeTranslationService() else {
            errorMessage = "Translation service not configured."
            phase = .failed
            return
        }
        let request = TranslationRequest(text: source, targetLanguage: settings.targetLanguage, tone: settings.tone, customTonePrompt: settings.customTonePrompt)
        do {
            let response = try await service.translate(request)
            translated = response.translatedText
            ExtensionBridge.appendHistory(source: source, translated: translated, language: settings.targetLanguage, tone: settings.tone)
            phase = .done
            if translated.count > 140 { context.expandSheet() }
        } catch {
            errorMessage = error.localizedDescription
            phase = .failed
        }
    }
}
