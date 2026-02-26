import Foundation

struct AppSettings: Codable {
    var targetLanguage: SupportedLanguage = .english
    var tone: Tone = .original
    var customTonePrompt: String = ""
    var autoPaste: Bool = true
    var selectedProvider: ProviderType = .claude

    // Shortcut stored as raw values.
    // Modifiers are fixed to Command + Shift; only the final letter is configurable.
    var shortcutKeyCode: UInt32 = ShortcutConfiguration.defaultOption.carbonKeyCode
    var shortcutModifiers: UInt = UInt(ShortcutConfiguration.fixedModifiers)

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: "appSettings"),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "appSettings")
        }
    }
}

enum ProviderType: String, Codable, CaseIterable, Identifiable {
    case claude = "Claude"
    case openAI = "OpenAI"
    case gemini = "Gemini"

    var id: String { rawValue }

    var apiKeyPlaceholder: String {
        switch self {
        case .claude:
            return "sk-ant-..."
        case .openAI:
            return "sk-..."
        case .gemini:
            return "AIza..."
        }
    }
}
