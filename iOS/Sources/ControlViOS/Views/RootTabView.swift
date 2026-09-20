import ControlVCore
import SwiftUI

struct RootTabView: View {
    @Environment(LicenseService.self) private var licenseService
    @State private var selection: Tab = Tab(rawValue: DebugLaunch.tab ?? "") ?? .translate
    /// Set by "Go Pro" while the trial is still running; the cover is also
    /// forced (non-dismissable) once the license is expired or invalid.
    @State private var paywallRequested = DebugLaunch.showPaywall
    @State private var showSetup = DebugLaunch.showSetup || !UserDefaults(suiteName: iOSSettingsStore.appGroup)!.bool(forKey: "hasSeenKeyboardSetup")

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
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
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
