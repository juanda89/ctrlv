import ControlVCore
import SwiftUI

@main
struct ControlViOSApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(coordinator.licenseService)
                .environment(coordinator.translationManager)
                .environment(coordinator.subscriptionManager)
                .environment(coordinator.settings)
                .task {
                    // Refresh subscription status on app launch and when becoming active
                    await coordinator.licenseService.refreshSubscriptionStatus(forceNetwork: true)
                    await coordinator.subscriptionManager.refreshOnLaunch()
                    // Mirror session token to App Group so Share + Keyboard
                    // extensions authenticate as this account.
                    AppGroupBridge.syncSessionToken(from: coordinator.licenseService)
                }
        }
    }
}

@MainActor
final class AppCoordinator: ObservableObject {
    let licenseService: LicenseService
    let translationManager: iOSTranslationManager
    let subscriptionManager: StoreKitSubscriptionManager
    let settings: iOSSettingsStore

    init() {
        let urlOpener: (URL) -> Void = { url in
            UIApplication.shared.open(url)
        }
        // Box so the onStateChange closure (installed before `license` exists)
        // can reference the service after construction.
        var serviceBox: LicenseService?
        let license = LicenseService(
            openURLHandler: urlOpener,
            startBackgroundTasks: true,
            onStateChange: { _ in
                // Keep the App Group token mirror fresh on EVERY state change —
                // this catches the automatic sign-out on 401 (session expired),
                // not just the manual sync points.
                guard let service = serviceBox else { return }
                AppGroupBridge.syncSessionToken(from: service)
            }
        )
        serviceBox = license
        self.licenseService = license
        self.translationManager = iOSTranslationManager(licenseService: license)
        self.subscriptionManager = StoreKitSubscriptionManager(licenseService: license)
        self.settings = iOSSettingsStore()
    }
}
