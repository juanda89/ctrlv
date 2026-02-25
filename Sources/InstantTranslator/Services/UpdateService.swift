import AppKit
import Foundation
import Sparkle

final class UpdateService: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private lazy var updaterController: SPUStandardUpdaterController = {
        SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
    }()
    private var didRunLaunchCheck = false

    override init() {
        super.init()
        _ = updaterController
    }

    @MainActor
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    /// Runs a background check once per app launch, so users can get an automatic
    /// "new version available" prompt without opening the menu manually.
    @MainActor
    func checkForUpdatesAtLaunchIfEnabled() {
        guard !didRunLaunchCheck else { return }
        guard updaterController.updater.automaticallyChecksForUpdates else { return }
        guard !updaterController.updater.sessionInProgress else { return }
        didRunLaunchCheck = true
        updaterController.updater.checkForUpdatesInBackground()
    }

    // MARK: - SPUStandardUserDriverDelegate

    nonisolated func standardUserDriverWillShowModalAlert() {
        // This is a menu bar app (LSUIElement). Bring it forward so the Sparkle
        // update alert is immediately visible to the user.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - SPUUpdaterDelegate

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
