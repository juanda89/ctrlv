import ControlVCore
import Foundation
import Observation

/// Persistent app settings backed by App Group UserDefaults so the
/// Share Extension can read the same target language + tone the user
/// chose in the main app.
@MainActor
@Observable
final class iOSSettingsStore {
    static let appGroup = "group.info.controlv.shared"

    var targetLanguage: SupportedLanguage {
        didSet { save() }
    }
    var tone: Tone {
        didSet { save() }
    }
    var customTonePrompt: String {
        didSet { save() }
    }

    private static let key = "iOSAppSettings"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    init() {
        if let data = Self.defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(Stored.self, from: data) {
            self.targetLanguage = decoded.targetLanguage
            self.tone = decoded.tone
            self.customTonePrompt = decoded.customTonePrompt
        } else {
            self.targetLanguage = .english
            self.tone = .original
            self.customTonePrompt = ""
        }
    }

    private func save() {
        let stored = Stored(
            targetLanguage: targetLanguage,
            tone: tone,
            customTonePrompt: customTonePrompt
        )
        if let data = try? JSONEncoder().encode(stored) {
            Self.defaults.set(data, forKey: Self.key)
        }
    }

    private struct Stored: Codable {
        var targetLanguage: SupportedLanguage
        var tone: Tone
        var customTonePrompt: String
    }
}
