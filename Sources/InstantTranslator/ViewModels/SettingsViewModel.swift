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

    var shortcutOptions: [ShortcutKeyOption] {
        ShortcutConfiguration.letterOptions
    }

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
        loaded.shortcutModifiers = UInt(ShortcutConfiguration.fixedModifiers)
        if !ShortcutConfiguration.isValid(keyCode: loaded.shortcutKeyCode) {
            loaded.shortcutKeyCode = ShortcutConfiguration.defaultOption.carbonKeyCode
        }

        self.settings = loaded
    }

    func setShortcut(_ option: ShortcutKeyOption) {
        settings.shortcutKeyCode = option.carbonKeyCode
        settings.shortcutModifiers = UInt(ShortcutConfiguration.fixedModifiers)
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
