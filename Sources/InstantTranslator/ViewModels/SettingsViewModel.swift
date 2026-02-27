import Foundation

@Observable
final class SettingsViewModel {
    var settings: AppSettings {
        didSet { settings.save() }
    }

    private var apiKeysByProvider: [ProviderType: String]

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

    init() {
        var loaded = AppSettings.load()
        loaded.shortcutModifiers = UInt(ShortcutConfiguration.fixedModifiers)
        if !ShortcutConfiguration.isValid(keyCode: loaded.shortcutKeyCode) {
            loaded.shortcutKeyCode = ShortcutConfiguration.defaultOption.carbonKeyCode
        }

        self.settings = loaded
        self.apiKeysByProvider = Dictionary(uniqueKeysWithValues: ProviderType.allCases.map { provider in
            (provider, EncryptedAPIKeyStore.read(for: provider) ?? "")
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
        if value.isEmpty {
            EncryptedAPIKeyStore.delete(for: provider)
        } else {
            EncryptedAPIKeyStore.save(value, for: provider)
        }
    }

    func apiKeyForSelectedProvider() -> String {
        apiKey(for: settings.selectedProvider)
    }
}
