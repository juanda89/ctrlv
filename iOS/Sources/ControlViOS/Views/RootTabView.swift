import ControlVCore
import SwiftUI

struct RootTabView: View {
    @Environment(LicenseService.self) private var licenseService
    // Account first: it carries the trial counter, upgrade and sign-in, and it
    // is where an unfinished setup is chased down.
    @State private var selection: Tab = Tab(rawValue: DebugLaunch.tab ?? "") ?? .account
    /// Set by "Go Pro" while the trial is still running; the cover is also
    /// forced (non-dismissable) once the license is expired or invalid.
    @State private var paywallRequested = DebugLaunch.showPaywall
    // Only on a first run that still cannot translate anywhere: a user who
    // already turned on either path never sees this sheet.
    // Shown until at least one path works: the app exists to translate inside
    // other apps, and none of that is reachable before setup.
    @State private var showSetup = DebugLaunch.showSetup || !SetupState.anyReady

    enum Tab: String { case translate, history, account }

    var body: some View {
        // Evaluated inside body so the license state is observed; a getter
        // inside the Binding runs outside tracking and never refreshes.
        let showPaywall = paywallRequested || mustShowPaywall
        ZStack {
            TabView(selection: $selection) {
                TranslateTabView()
                    .tabItem { Label("Translate", systemImage: "text.bubble") }
                    .tag(Tab.translate)
                HistoryTabView()
                    .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                    .tag(Tab.history)
                AccountTabView()
                    .tabItem { Label("Account", systemImage: "person.crop.circle") }
                    .tag(Tab.account)
            }
            .tint(Brand.blue)

            // An overlay, not a fullScreenCover: a cover requested in the same
            // run-loop turn the view appears (cached expired license, debug
            // override) can silently fail to present. The overlay is
            // deterministic and can't be swiped away when the license is expired.
            if showPaywall {
                PaywallView(preview: DebugLaunch.previewPricing, onClose: { paywallRequested = false })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .animation(.spring(duration: 0.35), value: showPaywall)
        .onReceive(NotificationCenter.default.publisher(for: .controlVShowPaywall)) { _ in
            paywallRequested = true
        }
        .sheet(isPresented: $showSetup) {
            KeyboardSetupView {
                UserDefaults(suiteName: iOSSettingsStore.appGroup)?.set(true, forKey: "hasSeenKeyboardSetup")
                showSetup = false
                NotificationCenter.default.post(name: .controlVSetupChanged, object: nil)
            }
            .presentationDetents([.large])
        }
    }

    /// `.checking` is the launch state; forcing the paywall there would flash
    /// it on every cold start before the cached license resolves.
    private var mustShowPaywall: Bool {
        switch licenseService.state {
        case .trial, .active, .checking: return false
        case .expired, .invalid: return true
        }
    }
}
