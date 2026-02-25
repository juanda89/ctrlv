import AppKit
import HotKey
import Carbon
import os

private let log = Logger(subsystem: "com.instanttranslator.app", category: "hotkey")

final class HotkeyService {
    private var hotKey: HotKey?
    var onTrigger: (() -> Void)?

    func register(carbonKeyCode: UInt32, carbonModifiers: UInt32, shortcutDisplay: String) {
        unregister()

        hotKey = HotKey(carbonKeyCode: carbonKeyCode, carbonModifiers: carbonModifiers)
        log.info("Registering global hotkey: \(shortcutDisplay, privacy: .public)")
        hotKey?.keyDownHandler = { [weak self] in
            log.info("Global hotkey event received")
            self?.onTrigger?()
        }
    }

    func unregister() {
        log.info("Unregistering global hotkey")
        hotKey = nil
    }
}
