import ControlVCore
import SwiftUI

struct TranslateTabView: View {
    @Environment(iOSTranslationManager.self) private var translation
    @Environment(iOSSettingsStore.self) private var settings

    @State private var inputText: String = ""
    @State private var resultText: String = ""
    @State private var isTranslating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Translate to") {
                    Picker("Language", selection: settingsBinding(\.targetLanguage)) {
                        ForEach(SupportedLanguage.allCases) { lang in
                            Text(lang.rawValue).tag(lang)
                        }
                    }
                    Picker("Tone", selection: settingsBinding(\.tone)) {
                        ForEach(Tone.allCases) { tone in
                            Text(tone.rawValue).tag(tone)
                        }
                    }
                }

                Section("Source text") {
                    TextEditor(text: $inputText)
                        .frame(minHeight: 120)
                        .scrollContentBackground(.hidden)

                    Button {
                        if let clipboardText = UIPasteboard.general.string {
                            inputText = clipboardText
                        }
                    } label: {
                        Label("Paste from clipboard", systemImage: "doc.on.clipboard")
                    }

                    Button {
                        Task { await runTranslation() }
                    } label: {
                        if isTranslating {
                            HStack {
                                ProgressView()
                                Text("Translating…")
                            }
                        } else {
                            Label("Translate", systemImage: "arrow.right.circle.fill")
                                .font(.body.weight(.semibold))
                        }
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isTranslating)
                }

                if !resultText.isEmpty {
                    Section("Result") {
                        Text(resultText)
                            .font(.body)
                            .textSelection(.enabled)

                        Button {
                            UIPasteboard.general.string = resultText
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Translate")
        }
    }

    private func settingsBinding<T>(_ keyPath: ReferenceWritableKeyPath<iOSSettingsStore, T>) -> Binding<T> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { settings[keyPath: keyPath] = $0 }
        )
    }

    private func runTranslation() async {
        errorMessage = nil
        isTranslating = true
        defer { isTranslating = false }

        do {
            let translated = try await translation.translate(
                text: inputText,
                targetLanguage: settings.targetLanguage,
                tone: settings.tone,
                customTonePrompt: settings.customTonePrompt
            )
            resultText = translated
            HistoryStore.shared.append(
                source: inputText,
                translated: translated,
                language: settings.targetLanguage,
                tone: settings.tone
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
