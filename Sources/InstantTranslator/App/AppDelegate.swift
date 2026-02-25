import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let updateService = UpdateService()
    private let userDefaults = UserDefaults.standard
    private let onboardingShownKey = "didShowInitialOnboarding"

    let licenseService = LicenseService()
    lazy var translatorViewModel = TranslatorViewModel(licenseService: licenseService)

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()

        // Hide dock icon — menu bar only
        NSApp.setActivationPolicy(.accessory)

        Task { @MainActor in
            await runInitialUserExperience()
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = defaultMenuBarIcon()
            if button.image == nil {
                // Make the menu bar app discoverable even if the symbol is unavailable.
                button.title = "V"
            }
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

    private func runInitialUserExperience() async {
        if needsMoveToApplications(),
           promptMoveToApplicationsIfNeeded() {
            return
        }

        if !userDefaults.bool(forKey: onboardingShownKey) {
            showPopoverIfPossible()
            userDefaults.set(true, forKey: onboardingShownKey)
        }

        await requestAccessibilityIfNeeded()
    }

    private func needsMoveToApplications() -> Bool {
        let bundlePath = Bundle.main.bundleURL.path
        return !bundlePath.hasPrefix("/Applications/")
    }

    @discardableResult
    private func promptMoveToApplicationsIfNeeded() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Install ctrl+v in Applications"
        alert.informativeText = "To keep permissions stable and avoid launch issues, move ctrl+v to /Applications before using it."
        alert.addButton(withTitle: "Move & Relaunch")
        alert.addButton(withTitle: "Continue Here")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            moveToApplicationsAndRelaunch()
            return true
        }

        return false
    }

    private func moveToApplicationsAndRelaunch() {
        let fileManager = FileManager.default
        let sourceURL = Bundle.main.bundleURL
        let destinationURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
            .appendingPathComponent(sourceURL.lastPathComponent)

        do {
            if sourceURL.path != destinationURL.path {
                if fileManager.fileExists(atPath: destinationURL.path) {
                    _ = try? fileManager.trashItem(at: destinationURL, resultingItemURL: nil)
                }
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            }

            NSWorkspace.shared.open(destinationURL)
            NSApp.terminate(nil)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Could not move ctrl+v automatically"
            alert.informativeText = "Move the app to /Applications manually, then open it again."
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    private func showPopoverIfPossible() {
        guard let button = statusItem.button, !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func requestAccessibilityIfNeeded() async {
        guard !AccessibilityService.isTrusted else { return }
        try? await Task.sleep(nanoseconds: 500_000_000)
        NSApp.activate(ignoringOtherApps: true)
        AccessibilityService.requestPermission()
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
