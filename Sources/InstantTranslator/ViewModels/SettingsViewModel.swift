import ControlVCore
import Foundation

@Observable
final class SettingsViewModel {
    var settings: AppSettings {
        didSet {
            if persistsToDisk {
                settings.save()
            }
            trackSettingsChanges(old: oldValue, new: settings)
        }
    }

    private let persistsToDisk: Bool

    // MARK: - Shortcut options (unchanged surface)

    var shortcutOptions: [ShortcutKeyOption] {
        ShortcutConfiguration.letterOptions
    }

    /// Selected shortcut of the primary profile (drives the header badge and
    /// the primary Behavior card).
    var selectedShortcutOption: ShortcutKeyOption {
        ShortcutConfiguration.option(for: settings.shortcutKeyCode)
    }

    var shortcutDisplay: String {
        "Command + Shift + \(selectedShortcutOption.letter)"
    }

    var shortcutKeyCaps: [String] {
        ["⌘", "⇧", selectedShortcutOption.letter]
    }

    var translationProvider: ProviderType {
        .ctrlVCloud
    }

    var translationEngineLabel: String {
        translationProvider.engineLabel
    }

    var translationModelLabel: String {
        translationProvider.modelLabel
    }

    init(persistToDisk: Bool = true) {
        self.persistsToDisk = persistToDisk

        var loaded = persistToDisk ? AppSettings.load() : AppSettings()

        // Sanitize each profile's shortcut in case a bad value was persisted
        // (e.g. deprecated keycode). Fall back to the default letter, but
        // avoid producing duplicates within the collection.
        var usedKeyCodes = Set<UInt32>()
        for i in 0..<loaded.profiles.count {
            if !ShortcutConfiguration.isValid(keyCode: loaded.profiles[i].shortcutKeyCode)
                || usedKeyCodes.contains(loaded.profiles[i].shortcutKeyCode) {
                loaded.profiles[i].shortcutKeyCode = Self.firstAvailableKeyCode(excluding: usedKeyCodes)
            }
            usedKeyCodes.insert(loaded.profiles[i].shortcutKeyCode)
        }
        if loaded.profiles.isEmpty {
            loaded.profiles = [TranslationProfile()]
        }

        self.settings = loaded
    }

    // MARK: - Primary profile shortcut (kept for compatibility)

    func setShortcut(_ option: ShortcutKeyOption) {
        setShortcut(option, forProfile: settings.profiles.first?.id ?? UUID())
    }

    // MARK: - Multi-profile CRUD

    /// Whether a new profile can be added (below the max cap).
    var canAddProfile: Bool {
        settings.profiles.count < TranslationProfile.maxProfiles
    }

    /// Add a new profile with defaults, assigning it the first available
    /// shortcut letter (avoids collisions with existing profiles).
    /// Returns the new profile's ID, or nil if the cap has been reached.
    @discardableResult
    func addProfile() -> UUID? {
        guard canAddProfile else { return nil }
        let used = Set(settings.profiles.map { $0.shortcutKeyCode })
        let keyCode = Self.firstAvailableKeyCode(excluding: used)
        let profile = TranslationProfile(shortcutKeyCode: keyCode)
        settings.profiles.append(profile)
        return profile.id
    }

    /// Remove a profile by id. The first profile cannot be removed — always
    /// keep at least one primary profile.
    func removeProfile(id: UUID) {
        guard let index = settings.profiles.firstIndex(where: { $0.id == id }) else { return }
        if index == 0 { return }
        settings.profiles.remove(at: index)
    }

    /// Set the shortcut letter of a specific profile. If another profile
    /// already uses that letter, this is a no-op — callers should check
    /// `isShortcutLetterAvailable` first and surface a UI error.
    func setShortcut(_ option: ShortcutKeyOption, forProfile profileID: UUID) {
        guard let index = settings.profiles.firstIndex(where: { $0.id == profileID }) else { return }
        if !isShortcutLetterAvailable(option.carbonKeyCode, excludingProfile: profileID) {
            return
        }
        settings.profiles[index].shortcutKeyCode = option.carbonKeyCode
    }

    /// True if this key code is free (not used by any OTHER profile).
    func isShortcutLetterAvailable(_ keyCode: UInt32, excludingProfile profileID: UUID) -> Bool {
        !settings.profiles.contains(where: { $0.id != profileID && $0.shortcutKeyCode == keyCode })
    }

    /// Update the language/tone/customPrompt of a profile in one shot.
    func updateProfile(
        id: UUID,
        targetLanguage: SupportedLanguage? = nil,
        tone: Tone? = nil,
        customTonePrompt: String? = nil
    ) {
        guard let index = settings.profiles.firstIndex(where: { $0.id == id }) else { return }
        if let targetLanguage { settings.profiles[index].targetLanguage = targetLanguage }
        if let tone { settings.profiles[index].tone = tone }
        if let customTonePrompt { settings.profiles[index].customTonePrompt = customTonePrompt }
    }

    /// Read helpers for a specific profile — SwiftUI views bind via these.
    func binding(forProfile id: UUID) -> TranslationProfile? {
        settings.profiles.first(where: { $0.id == id })
    }

    // MARK: - Private helpers

    private static func firstAvailableKeyCode(excluding used: Set<UInt32>) -> UInt32 {
        for option in ShortcutConfiguration.letterOptions {
            if !used.contains(option.carbonKeyCode) {
                return option.carbonKeyCode
            }
        }
        return ShortcutConfiguration.defaultOption.carbonKeyCode
    }

    private func trackSettingsChanges(old: AppSettings, new: AppSettings) {
        if old.targetLanguage != new.targetLanguage {
            TelemetryService.trackLanguageChanged(new.targetLanguage)
        }
        if old.tone != new.tone {
            TelemetryService.trackToneChanged(new.tone)
        }
        if old.autoPaste != new.autoPaste {
            TelemetryService.trackAutoPasteToggled(enabled: new.autoPaste)
        }
    }
}
