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
        let license = LicenseService(
            openURLHandler: urlOpener,
            startBackgroundTasks: true,
            onStateChange: nil
        )
        self.licenseService = license
        self.translationManager = iOSTranslationManager(licenseService: license)
        self.subscriptionManager = StoreKitSubscriptionManager(licenseService: license)
        self.settings = iOSSettingsStore()
    }
}
