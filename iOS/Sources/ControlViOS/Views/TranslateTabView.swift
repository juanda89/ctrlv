import ControlVCore
import SwiftUI

struct TranslateTabView: View {
    @Environment(iOSTranslationManager.self) private var translation
    @Environment(iOSSettingsStore.self) private var settings

    @State private var inputText: String = DebugLaunch.sourceText ?? ""
    @State private var resultText: String = ""
    @State private var isTranslating = false
    @State private var errorMessage: String?
    @State private var showToast = false
    @State private var showSetup = false
    @FocusState private var editorFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LanguagePairRow(target: settingsBinding(\.targetLanguage))

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "Tone")
                        ToneChipRow(tone: settingsBinding(\.tone))
                        if settings.tone == .custom {
                            TextField("Describe the style, e.g. friendly startup tone, short sentences", text: settingsBinding(\.customTonePrompt), axis: .vertical)
                                .lineLimit(2...4)
                                .font(.subheadline)
                                .padding(12)
                                .glassCard(16)
                        }
                    }

                    editorCard

                    Button {
                        editorFocused = false
                        Task { await runTranslation() }
                    } label: {
                        if isTranslating {
                            HStack(spacing: 10) { ProgressView().tint(.white); Text("Translating…") }
                        } else {
                            Label("Translate", systemImage: "arrow.right")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTranslating)

                    if !resultText.isEmpty { resultCard }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.orange)
                            .padding(12)
                            .glassCard(14)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AuroraBackground())
            .navigationTitle("Translate")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSetup = true } label: { Image(systemName: "keyboard") }
                        .accessibilityLabel("Set up the keyboard")
                }
            }
            .sheet(isPresented: $showSetup) {
                KeyboardSetupView { showSetup = false }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .toast("Copied", isPresented: $showToast)
            .task {
                if DebugLaunch.autoTranslate, !inputText.isEmpty { await runTranslation() }
            }
        }
    }

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                if inputText.isEmpty {
                    Text("Type or paste anything…")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                }
                TextEditor(text: $inputText)
                    .font(.title3)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 150)
                    .focused($editorFocused)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            HStack {
                Text("\(inputText.count) characters")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                Spacer()
                if !inputText.isEmpty {
                    Button { inputText = ""; resultText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain)
                        .padding(.trailing, 4)
                }
                Button {
                    if let clipboard = UIPasteboard.general.string { inputText = clipboard }
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(GlassButtonStyle())
            }
            .padding(12)
        }
        .glassCard(22)
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: settings.targetLanguage.rawValue)
                Spacer()
                Text(settings.tone.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(resultText)
                .font(.title3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button {
                    UIPasteboard.general.string = resultText
                    withAnimation { showToast = true }
                } label: { Label("Copy", systemImage: "doc.on.doc") }
                .buttonStyle(GlassButtonStyle())
                ShareLink(item: resultText) { Label("Share", systemImage: "square.and.arrow.up") }
                    .buttonStyle(GlassButtonStyle())
                Spacer()
                Button { showSetup = true } label: {
                    Label("Replace in any app", systemImage: "keyboard")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .glassCard(22)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func settingsBinding<T>(_ keyPath: ReferenceWritableKeyPath<iOSSettingsStore, T>) -> Binding<T> {
        Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0 })
    }

    private func runTranslation() async {
        errorMessage = nil
        isTranslating = true
        defer { isTranslating = false }
        do {
            let translated = try await translation.translate(text: inputText, targetLanguage: settings.targetLanguage, tone: settings.tone, customTonePrompt: settings.customTonePrompt)
            withAnimation(.spring(duration: 0.4)) { resultText = translated }
            HistoryStore.shared.append(source: inputText, translated: translated, language: settings.targetLanguage, tone: settings.tone)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
