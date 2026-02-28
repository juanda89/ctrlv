import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let updateService = UpdateService()
    private let userDefaults = UserDefaults.standard
    private let onboardingShownKey = "didShowInitialOnboarding"
    private let accessibilityPromptShownKey = "didRequestAccessibilityPermission"
    private let accessibilityGrantedKey = "didGrantAccessibilityPermission"
    private let clickDebounceInterval: TimeInterval = 0.3
    private var lastClickDate = Date.distantPast
    private let translationIslandOverlay = TranslationIslandOverlayController()

    let licenseService = LicenseService()
    lazy var translatorViewModel: TranslatorViewModel = {
        let vm = TranslatorViewModel(licenseService: licenseService)
        vm.appDelegate = self
        return vm
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()

        // Hide dock icon — menu bar only
        NSApp.setActivationPolicy(.accessory)
        registerLaunchAtLogin()

        Task { @MainActor in
            await runPostInstallUserExperience()
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            updateService.checkForUpdatesAtLaunchIfEnabled()
            updateService.startPeriodicBackgroundChecks()
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
                updateService: updateService,
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

    private func showPopoverIfPossible() {
        guard let button = statusItem.button, !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func requestAccessibilityIfNeeded() async {
        if AccessibilityService.isTrusted {
            userDefaults.set(true, forKey: accessibilityGrantedKey)
            return
        }

        // If this app was already granted before, avoid showing system prompts again.
        // Trust should persist naturally across updates when release builds use stable signing.
        if userDefaults.bool(forKey: accessibilityGrantedKey) {
            return
        }

        // First-time request only.
        guard !userDefaults.bool(forKey: accessibilityPromptShownKey) else { return }
        userDefaults.set(true, forKey: accessibilityPromptShownKey)

        try? await Task.sleep(nanoseconds: 500_000_000)

        // Re-check after delay to avoid prompting from transient startup states.
        if AccessibilityService.isTrusted {
            userDefaults.set(true, forKey: accessibilityGrantedKey)
            return
        }

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

    /// Show the translation island overlay.
    func showTranslatingIcon() {
        translationIslandOverlay.show()
    }

    /// Restore the default menu bar icon.
    func restoreDefaultIcon() {
        translationIslandOverlay.hide()
        guard let button = statusItem.button else { return }
        button.image = defaultMenuBarIcon()
    }

    /// Debug utility to verify the translation island can be rendered.
    func debugShowTranslationIslandPreview() {
        translationIslandOverlay.debugPulse()
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
