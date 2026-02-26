import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var installerWindow: NSWindow?
    private let updateService = UpdateService()
    private let userDefaults = UserDefaults.standard
    private let onboardingShownKey = "didShowInitialOnboarding"
    private let clickDebounceInterval: TimeInterval = 0.3
    private var lastClickDate = Date.distantPast
    private let installerState = InstallerWindowState()
    private let translationIslandOverlay = TranslationIslandOverlayController()

    let licenseService = LicenseService()
    lazy var translatorViewModel = TranslatorViewModel(licenseService: licenseService)

    func applicationDidFinishLaunching(_ notification: Notification) {
        if needsInstallation() {
            presentInstallerWindow()
            return
        }

        setupMenuBar()

        // Hide dock icon — menu bar only
        NSApp.setActivationPolicy(.accessory)
        registerLaunchAtLogin()

        Task { @MainActor in
            await runPostInstallUserExperience()
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            updateService.checkForUpdatesAtLaunchIfEnabled()
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

    private func runPostInstallUserExperience() async {
        if !userDefaults.bool(forKey: onboardingShownKey) {
            showPopoverIfPossible()
            userDefaults.set(true, forKey: onboardingShownKey)
        }

        await requestAccessibilityIfNeeded()
    }

    private func needsInstallation() -> Bool {
        let bundlePath = Bundle.main.bundleURL.path
        let userApplicationsPrefix = "\(NSHomeDirectory())/Applications/"
        return !(bundlePath.hasPrefix("/Applications/") || bundlePath.hasPrefix(userApplicationsPrefix))
    }

    private func preferredInstallDestinationURL() -> URL {
        let appName = Bundle.main.bundleURL.lastPathComponent
        return URL(fileURLWithPath: "/Applications", isDirectory: true).appendingPathComponent(appName)
    }

    private func fallbackInstallDestinationURL() -> URL {
        let appName = Bundle.main.bundleURL.lastPathComponent
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent(appName)
    }

    private func presentInstallerWindow() {
        NSApp.setActivationPolicy(.regular)

        let destinationHint = preferredInstallDestinationURL().path
        let rootView = InstallerWindowView(
            state: installerState,
            destinationHint: destinationHint,
            onInstall: { [weak self] in
                Task { @MainActor in
                    await self?.installAndRelaunch()
                }
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 260),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "Install ctrl+v"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: rootView)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        installerWindow = window
    }

    private func installAndRelaunch() async {
        guard !installerState.isInstalling else { return }

        installerState.isInstalling = true
        installerState.errorMessage = nil

        let fileManager = FileManager.default
        let sourceURL = Bundle.main.bundleURL
        let destinations = [preferredInstallDestinationURL(), fallbackInstallDestinationURL()]
        var errors: [String] = []

        for destinationURL in destinations {
            do {
                try fileManager.createDirectory(
                    at: destinationURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true,
                    attributes: nil
                )

                if sourceURL.path != destinationURL.path {
                    if fileManager.fileExists(atPath: destinationURL.path) {
                        _ = try? fileManager.trashItem(at: destinationURL, resultingItemURL: nil)
                        if fileManager.fileExists(atPath: destinationURL.path) {
                            try fileManager.removeItem(at: destinationURL)
                        }
                    }
                    try fileManager.copyItem(at: sourceURL, to: destinationURL)
                }

                installerState.isInstalling = false
                NSWorkspace.shared.open(destinationURL)
                NSApp.terminate(nil)
                return
            } catch {
                errors.append("\(destinationURL.path): \(error.localizedDescription)")
            }
        }

        installerState.isInstalling = false
        installerState.errorMessage = """
        Could not install automatically.
        Try drag-and-drop to /Applications and open again.
        \(errors.joined(separator: "\n"))
        """
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

    private func registerLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            switch service.status {
            case .enabled:
                return
            case .notRegistered, .requiresApproval, .notFound:
                try service.register()
            @unknown default:
                try service.register()
            }
        } catch {
            // Non-fatal: app remains usable even if login-item registration fails.
            print("Launch-at-login registration failed: \(error.localizedDescription)")
        }
    }

    @objc private func togglePopover() {
        let now = Date()
        guard now.timeIntervalSince(lastClickDate) > clickDebounceInterval else { return }
        lastClickDate = now

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
        translationIslandOverlay.show()
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "Translating")
    }

    /// Restore the default menu bar icon.
    func restoreDefaultIcon() {
        translationIslandOverlay.hide()
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
