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

    private var apiKeysByProvider: [ProviderType: String]
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

    var apiKeyPlaceholder: String {
        "\(settings.selectedProvider.rawValue) API Key: \(settings.selectedProvider.apiKeyPlaceholder)"
    }

    init(persistToDisk: Bool = true) {
        self.persistsToDisk = persistToDisk

        var loaded = persistToDisk ? AppSettings.load() : AppSettings()
        loaded.shortcutModifiers = UInt(ShortcutConfiguration.fixedModifiers)
        if !ShortcutConfiguration.isValid(keyCode: loaded.shortcutKeyCode) {
            loaded.shortcutKeyCode = ShortcutConfiguration.defaultOption.carbonKeyCode
        }

        self.settings = loaded
        self.apiKeysByProvider = Dictionary(uniqueKeysWithValues: ProviderType.allCases.map { provider in
            let value = persistToDisk ? (EncryptedAPIKeyStore.read(for: provider) ?? "") : ""
            return (provider, value)
        })
    }

    func setShortcut(_ option: ShortcutKeyOption) {
        settings.shortcutKeyCode = option.carbonKeyCode
        settings.shortcutModifiers = UInt(ShortcutConfiguration.fixedModifiers)
    }

    func apiKey(for provider: ProviderType) -> String {
        apiKeysByProvider[provider] ?? ""
    }

    func setAPIKey(_ value: String, for provider: ProviderType) {
        apiKeysByProvider[provider] = value
        guard persistsToDisk else { return }

        if value.isEmpty {
            EncryptedAPIKeyStore.delete(for: provider)
        } else {
            EncryptedAPIKeyStore.save(value, for: provider)
            TelemetryService.trackAPIKeyAdded(provider: provider)
        }
    }

    func apiKeyForSelectedProvider() -> String {
        apiKey(for: settings.selectedProvider)
    }

    private func trackSettingsChanges(old: AppSettings, new: AppSettings) {
        if old.targetLanguage != new.targetLanguage {
            TelemetryService.trackLanguageChanged(new.targetLanguage)
        }
        if old.tone != new.tone {
            TelemetryService.trackToneChanged(new.tone)
        }
        if old.selectedProvider != new.selectedProvider {
            TelemetryService.trackProviderChanged(new.selectedProvider)
        }
        if old.autoPaste != new.autoPaste {
            TelemetryService.trackAutoPasteToggled(enabled: new.autoPaste)
        }
    }
}
