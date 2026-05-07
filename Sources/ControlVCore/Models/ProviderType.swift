import Foundation

public enum ProviderType: String, Codable, CaseIterable, Identifiable, Sendable {
    case ctrlVCloud = "ctrl+v Cloud"
    case claude = "Claude"
    case openAI = "OpenAI"
    case gemini = "Gemini"

    public var id: String { rawValue }

    public var apiKeyPlaceholder: String {
        switch self {
        case .ctrlVCloud:
            return ""
        case .claude:
            return "sk-ant-..."
        case .openAI:
            return "sk-..."
        case .gemini:
            return "AIza..."
        }
    }

    public var apiKeyHelpTitle: String {
        "How to get your \(rawValue) API key"
    }

    public var apiKeyHelpSubtitle: String {
        switch self {
        case .ctrlVCloud:
            return "ctrl+v Cloud is managed by the app and does not need a user API key."
        case .claude:
            return "Create a key in Anthropic Console and paste it in ctrl+v."
        case .openAI:
            return "Create a key in OpenAI Platform and paste it in ctrl+v."
        case .gemini:
            return "Create a key in Google AI Studio and paste it in ctrl+v."
        }
    }

    public var apiKeyHelpSteps: [String] {
        switch self {
        case .ctrlVCloud:
            return [
                "No setup required.",
                "ctrl+v routes translations through its managed backend.",
                "Usage limits are enforced automatically based on trial or active license."
            ]
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

    public var apiKeyHelpURL: URL? {
        switch self {
        case .ctrlVCloud:
            return nil
        case .claude:
            return URL(string: "https://console.anthropic.com/settings/keys")
        case .openAI:
            return URL(string: "https://platform.openai.com/api-keys")
        case .gemini:
            return URL(string: "https://aistudio.google.com/app/apikey")
        }
    }

    public var engineLabel: String {
        switch self {
        case .ctrlVCloud:
            return Constants.hostedEngineName
        case .claude:
            return "Anthropic"
        case .openAI:
            return "OpenAI"
        case .gemini:
            return "Google"
        }
    }

    public var modelLabel: String {
        switch self {
        case .ctrlVCloud:
            return Constants.hostedModelName
        case .claude:
            return "claude-4-6-opus"
        case .openAI:
            return "gpt-5.2"
        case .gemini:
            return "gemini-3.1-pro"
        }
    }
}
