import ControlVCore
import Foundation

/// Settings the main app writes to the App Group (`iOSSettingsStore`), read
/// by the Share, Keyboard and Translation extensions.
struct ExtensionSettings {
    var targetLanguage: SupportedLanguage = .english
    var tone: Tone = .original
    var customTonePrompt: String = ""
}

/// App Group access shared by every extension: settings, install ID, session
/// token (mirrored by `AppGroupBridge` on sign-in) and the local history that
/// the app's History tab shows. Keys and shapes mirror the main app's stores.
enum ExtensionBridge {
    static let appGroup = "group.info.controlv.shared"
    private static let settingsKey = "iOSAppSettings"
    private static let installIDKey = "ctrlvInstallID"
    private static let sessionTokenKey = "iOSSessionToken"
    private static let historyKey = "iOSHistory"
    private static let maxHistoryEntries = 50

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    // MARK: Settings

    static func loadSettings() -> ExtensionSettings {
        guard let data = defaults.data(forKey: settingsKey),
              let stored = try? JSONDecoder().decode(StoredSettings.self, from: data) else {
            return ExtensionSettings()
        }
        return ExtensionSettings(targetLanguage: stored.targetLanguage, tone: stored.tone, customTonePrompt: stored.customTonePrompt)
    }

    static func save(_ settings: ExtensionSettings) {
        let stored = StoredSettings(targetLanguage: settings.targetLanguage, tone: settings.tone, customTonePrompt: settings.customTonePrompt)
        if let data = try? JSONEncoder().encode(stored) { defaults.set(data, forKey: settingsKey) }
    }

    // MARK: Identity

    static func installID() -> String {
        if let existing = defaults.string(forKey: installIDKey), !existing.isEmpty {
            return existing
        }
        let new = UUID().uuidString.lowercased()
        defaults.set(new, forKey: installIDKey)
        return new
    }

    static func sessionToken() -> String? {
        defaults.string(forKey: sessionTokenKey)
    }

    /// Cloud translation service authenticated as this install / account.
    /// Usage limits (trial quota, character caps) are enforced server-side.
    static func makeTranslationService() -> TranslationService? {
        guard let endpoint = Constants.translationAPIURL else { return nil }
        let provider = CtrlVCloudProvider(endpoint: endpoint, installID: installID(), sessionToken: sessionToken())
        return TranslationService(provider: provider)
    }

    // MARK: History

    static func appendHistory(source: String, translated: String, language: SupportedLanguage, tone: Tone) {
        var entries = defaults.data(forKey: historyKey).flatMap { try? JSONDecoder().decode([HistoryRecord].self, from: $0) } ?? []
        entries.insert(HistoryRecord(id: UUID(), source: source, translated: translated, language: language, tone: tone, timestamp: Date()), at: 0)
        if entries.count > maxHistoryEntries { entries = Array(entries.prefix(maxHistoryEntries)) }
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: historyKey) }
    }

    private struct StoredSettings: Codable {
        var targetLanguage: SupportedLanguage
        var tone: Tone
        var customTonePrompt: String
    }

    /// Same shape as the app's `HistoryEntry`.
    private struct HistoryRecord: Codable {
        let id: UUID
        let source: String
        let translated: String
        let language: SupportedLanguage
        let tone: Tone
        let timestamp: Date
    }
}
