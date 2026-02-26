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

    var apiKeyHelpTitle: String {
        "How to get your \(rawValue) API key"
    }

    var apiKeyHelpSubtitle: String {
        switch self {
        case .claude:
            return "Create a key in Anthropic Console and paste it in ctrl+v."
        case .openAI:
            return "Create a key in OpenAI Platform and paste it in ctrl+v."
        case .gemini:
            return "Create a key in Google AI Studio and paste it in ctrl+v."
        }
    }

    var apiKeyHelpSteps: [String] {
        switch self {
        case .claude:
            return [
                "Sign in to Anthropic Console.",
                "Open Settings > API Keys and click Create Key.",
                "Copy the key and paste it into ctrl+v."
            ]
        case .openAI:
            return [
                "Sign in to OpenAI Platform.",
                "Open API Keys and click Create new secret key.",
                "Copy the key and paste it into ctrl+v."
            ]
        case .gemini:
            return [
                "Sign in to Google AI Studio.",
                "Open Get API key and create a new key.",
                "Copy the key and paste it into ctrl+v."
            ]
        }
    }

    var apiKeyHelpURL: URL? {
        switch self {
        case .claude:
            return URL(string: "https://console.anthropic.com/settings/keys")
        case .openAI:
            return URL(string: "https://platform.openai.com/api-keys")
        case .gemini:
            return URL(string: "https://aistudio.google.com/app/apikey")
        }
    }
}
