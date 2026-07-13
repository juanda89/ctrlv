import ControlVCore
import Foundation

struct AppSettings: Codable {
    /// Global behavior flag. Applies to every profile.
    var autoPaste: Bool = true

    /// One or more translation profiles. `profiles[0]` is the "primary" and
    /// drives the main popover UI (language/tone/shortcut sections). Additional
    /// profiles (up to `TranslationProfile.maxProfiles - 1`) are exposed only
    /// through the Advanced panel.
    var profiles: [TranslationProfile]

    // MARK: - Primary profile convenience accessors
    //
    // The primary popover UI (PreferencesSection, BehaviorSection, MenuBarView)
    // has always operated on top-level fields. Keeping these as computed
    // properties over `profiles[0]` means the existing SwiftUI bindings — and
    // downstream reads in TranslatorViewModel — keep working unchanged when
    // the app hasn't been re-architected for multi-profile yet.

    var targetLanguage: SupportedLanguage {
        get { primaryProfile.targetLanguage }
        set { updatePrimary { $0.targetLanguage = newValue } }
    }

    var tone: Tone {
        get { primaryProfile.tone }
        set { updatePrimary { $0.tone = newValue } }
    }

    var customTonePrompt: String {
        get { primaryProfile.customTonePrompt }
        set { updatePrimary { $0.customTonePrompt = newValue } }
    }

    var shortcutKeyCode: UInt32 {
        get { primaryProfile.shortcutKeyCode }
        set { updatePrimary { $0.shortcutKeyCode = newValue } }
    }

    var shortcutModifiers: UInt {
        get { UInt(ShortcutConfiguration.fixedModifiers) }
        set { _ = newValue /* modifiers are fixed; kept for legacy encoding */ }
    }

    var primaryProfile: TranslationProfile {
        profiles.first ?? TranslationProfile()
    }

    private mutating func updatePrimary(_ mutate: (inout TranslationProfile) -> Void) {
        if profiles.isEmpty {
            profiles.append(TranslationProfile())
        }
        mutate(&profiles[0])
    }

    // MARK: - Defaults

    init(
        autoPaste: Bool = true,
        profiles: [TranslationProfile] = [TranslationProfile()]
    ) {
        self.autoPaste = autoPaste
        self.profiles = profiles.isEmpty ? [TranslationProfile()] : profiles
    }

    // MARK: - Persistence

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: "appSettings") else {
            return AppSettings()
        }
        do {
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            return AppSettings()
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "appSettings")
        }
    }

    // MARK: - Codable with backward compatibility
    //
    // Old payloads (pre-2.1.0) store `targetLanguage`, `tone`, `customTonePrompt`,
    // `shortcutKeyCode`, `shortcutModifiers` at the top level and DO NOT have a
    // `profiles` array. On decode: if `profiles` is missing, synthesize one
    // profile from the legacy fields so existing users' settings survive.
    //
    // On encode: we also write the legacy fields (mirroring profile[0]) so a
    // downgrade to a pre-2.1.0 build still finds the primary settings.

    enum CodingKeys: String, CodingKey {
        case autoPaste
        case profiles
        case targetLanguage
        case tone
        case customTonePrompt
        case shortcutKeyCode
        case shortcutModifiers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.autoPaste = try c.decodeIfPresent(Bool.self, forKey: .autoPaste) ?? true

        if let profiles = try c.decodeIfPresent([TranslationProfile].self, forKey: .profiles),
           !profiles.isEmpty {
            self.profiles = profiles
            return
        }

        // Legacy shape — build a single profile from the flat fields.
        let legacyLanguage = try c.decodeIfPresent(SupportedLanguage.self, forKey: .targetLanguage) ?? .english
        let legacyTone = try c.decodeIfPresent(Tone.self, forKey: .tone) ?? .original
        let legacyCustom = try c.decodeIfPresent(String.self, forKey: .customTonePrompt) ?? ""
        let legacyKeyCode = try c.decodeIfPresent(UInt32.self, forKey: .shortcutKeyCode)
            ?? ShortcutConfiguration.defaultOption.carbonKeyCode

        self.profiles = [
            TranslationProfile(
                targetLanguage: legacyLanguage,
                tone: legacyTone,
                customTonePrompt: legacyCustom,
                shortcutKeyCode: legacyKeyCode
            )
        ]
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(autoPaste, forKey: .autoPaste)
        try c.encode(profiles, forKey: .profiles)

        // Legacy mirror so an old build reading this JSON still finds settings.
        let primary = profiles.first ?? TranslationProfile()
        try c.encode(primary.targetLanguage, forKey: .targetLanguage)
        try c.encode(primary.tone, forKey: .tone)
        try c.encode(primary.customTonePrompt, forKey: .customTonePrompt)
        try c.encode(primary.shortcutKeyCode, forKey: .shortcutKeyCode)
        try c.encode(UInt(ShortcutConfiguration.fixedModifiers), forKey: .shortcutModifiers)
    }
}
