import ControlVCore
import SwiftUI

struct RootTabView: View {
    @Environment(LicenseService.self) private var licenseService

    var body: some View {
        // If user must subscribe (no active subscription, no remaining trial),
        // show the paywall as a full-screen cover. Otherwise show the tabs.
        TabView {
            TranslateTabView()
                .tabItem {
                    Label("Translate", systemImage: "text.bubble")
                }

            HistoryTabView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }

            AccountTabView()
                .tabItem {
                    Label("Account", systemImage: "person.crop.circle")
                }
        }
        .fullScreenCover(isPresented: .constant(shouldShowPaywall)) {
            PaywallView()
        }
    }

    private var shouldShowPaywall: Bool {
        // Show paywall if user has no usable state.
        // Trial state allows usage; expired/invalid require subscription.
        switch licenseService.state {
        case .trial, .active:
            return false
        case .expired, .invalid, .checking:
            return true
        }
    }
}
