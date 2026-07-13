import ControlVCore
import Foundation

/// A named translation profile bound to its own global shortcut. The user can
/// have up to `maxProfiles` in parallel, each with a distinct shortcut letter,
/// target language, tone, and (optional) custom tone prompt.
///
/// Auto-paste stays global on `AppSettings` — it is a behavior flag rather
/// than a translation-shape flag.
struct TranslationProfile: Codable, Identifiable, Equatable {
    let id: UUID
    var targetLanguage: SupportedLanguage
    var tone: Tone
    var customTonePrompt: String
    var shortcutKeyCode: UInt32

    static let maxProfiles = 3

    init(
        id: UUID = UUID(),
        targetLanguage: SupportedLanguage = .english,
        tone: Tone = .original,
        customTonePrompt: String = "",
        shortcutKeyCode: UInt32 = ShortcutConfiguration.defaultOption.carbonKeyCode
    ) {
        self.id = id
        self.targetLanguage = targetLanguage
        self.tone = tone
        self.customTonePrompt = customTonePrompt
        self.shortcutKeyCode = shortcutKeyCode
    }

    /// Human-readable label used in menus and cards: "⌘⇧V · English · Original".
    func displayLabel(shortcutLetter: String) -> String {
        "⌘⇧\(shortcutLetter) · \(targetLanguage.rawValue) · \(tone.rawValue)"
    }

    var shortcutLetter: String {
        ShortcutConfiguration.option(for: shortcutKeyCode).letter
    }
}
