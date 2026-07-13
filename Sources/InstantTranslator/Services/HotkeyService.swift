import AppKit
import HotKey
import Carbon
import os

private let log = Logger(subsystem: "com.instanttranslator.app", category: "hotkey")

/// A profile-aware hotkey registration.
struct HotkeyBinding {
    let profileID: UUID
    let carbonKeyCode: UInt32
    let displayLabel: String
}

final class HotkeyService {
    private var hotKeys: [UUID: HotKey] = [:]

    /// Fired when any registered hotkey is pressed. The profile UUID identifies
    /// which one triggered so the view model can route to the correct
    /// language/tone.
    var onTrigger: ((UUID) -> Void)?

    /// Register (or replace) the full set of hotkeys. Any previously
    /// registered hotkeys are removed first — this keeps the collection in
    /// sync with the current profile list.
    func registerAll(_ bindings: [HotkeyBinding]) {
        unregisterAll()

        let modifiers = ShortcutConfiguration.fixedModifiers

        for binding in bindings {
            let hotkey = HotKey(carbonKeyCode: binding.carbonKeyCode, carbonModifiers: modifiers)
            let profileID = binding.profileID
            log.info("Registering global hotkey: \(binding.displayLabel, privacy: .public) → \(profileID.uuidString, privacy: .public)")
            hotkey.keyDownHandler = { [weak self] in
                log.info("Global hotkey event received for profile \(profileID.uuidString, privacy: .public)")
                self?.onTrigger?(profileID)
            }
            hotKeys[profileID] = hotkey
        }
    }

    func unregisterAll() {
        if !hotKeys.isEmpty {
            log.info("Unregistering \(self.hotKeys.count) hotkey(s)")
        }
        hotKeys.removeAll()
    }
}
