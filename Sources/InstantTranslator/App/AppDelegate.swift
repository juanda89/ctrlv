import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let updateService = UpdateService()

    let licenseService = LicenseService()
    lazy var translatorViewModel = TranslatorViewModel(licenseService: licenseService)

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()

        // Hide dock icon — menu bar only
        NSApp.setActivationPolicy(.accessory)

        // Check accessibility on launch
        if !AccessibilityService.isTrusted {
            AccessibilityService.requestPermission()
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = defaultMenuBarIcon()
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 336, height: 560)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(
                viewModel: translatorViewModel,
                licenseService: licenseService,
                onOpenFeedback: { [weak self] in self?.openFeedback() },
                onCheckForUpdates: { [weak self] in self?.updateService.checkForUpdates() },
                onShowAbout: { [weak self] in self?.showAbout() }
            )
        )
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    /// Flash the menu bar icon to a checkmark briefly, then restore.
    func flashMenuBarIcon() {
        guard let button = statusItem.button else { return }
        let original = button.image
        button.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Done")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            button.image = original
        }
    }

    /// Show a loading indicator on the menu bar icon.
    func showTranslatingIcon() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "Translating")
    }

    /// Restore the default menu bar icon.
    func restoreDefaultIcon() {
        guard let button = statusItem.button else { return }
        button.image = defaultMenuBarIcon()
    }

    private func defaultMenuBarIcon() -> NSImage? {
        NSImage(systemSymbolName: "v.square", accessibilityDescription: "ctrl+v")
    }

    private func openFeedback() {
        guard let url = Constants.feedbackURL else { return }
        NSWorkspace.shared.open(url)
    }

    private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}
