import Foundation

@Observable
final class SettingsViewModel {
    var settings: AppSettings {
        didSet { settings.save() }
    }

    var apiKey: String {
        didSet {
            if apiKey.isEmpty {
                EncryptedAPIKeyStore.delete()
            } else {
                EncryptedAPIKeyStore.save(apiKey)
            }
        }
    }

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

    init() {
        var loaded = AppSettings.load()
        loaded.shortcutModifiers = UInt(ShortcutConfiguration.fixedModifiers)
        if !ShortcutConfiguration.isValid(keyCode: loaded.shortcutKeyCode) {
            loaded.shortcutKeyCode = ShortcutConfiguration.defaultOption.carbonKeyCode
        }

        self.settings = loaded
        self.apiKey = EncryptedAPIKeyStore.read() ?? ""
    }

    func setShortcut(_ option: ShortcutKeyOption) {
        settings.shortcutKeyCode = option.carbonKeyCode
        settings.shortcutModifiers = UInt(ShortcutConfiguration.fixedModifiers)
    }
}
