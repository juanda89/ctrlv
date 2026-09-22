import ControlVCore
import Foundation
import SwiftUI

/// Launch arguments (NSUserDefaults argument domain) used for headless
/// screenshots and QA: `xcrun simctl launch <udid> info.controlv.ios -ui.tab account`.
/// Never set by real users; every value is optional.
enum DebugLaunch {
#if DEBUG
    private static let d = UserDefaults.standard
    static var tab: String? { d.string(forKey: "ui.tab") }
    static var showPaywall: Bool { d.bool(forKey: "ui.showPaywall") }
    static var showSignIn: Bool { d.bool(forKey: "ui.showSignIn") }
    static var showSetup: Bool { d.bool(forKey: "ui.showSetup") }
    static var showFeedback: Bool { d.bool(forKey: "ui.showFeedback") }
    static var sourceText: String? { d.string(forKey: "ui.sourceText") }
    static var autoTranslate: Bool { d.bool(forKey: "ui.autoTranslate") }
    static var seedHistory: Bool { d.bool(forKey: "ui.seedHistory") }
    /// Renders the paywall with a fixed price/trial (App Review screenshot):
    /// StoreKit only serves the product when the app runs from a scheme with a
    /// StoreKit configuration, so a simctl launch would show the error state.
    static var previewPricing: PaywallView.Preview? {
        d.bool(forKey: "ui.previewPricing") ? .init(priceText: "$4.99", trialDays: 14) : nil
    }
    /// Forces the recorded setup state so the account and setup screens can be
    /// captured in every configuration: none, one path on, both on.
    static var setupState: String? { d.string(forKey: "ui.setupState") }
    /// Renders the signed-in account card without a real session (screenshots).
    static var fakeSignedIn: Bool { d.bool(forKey: "ui.fakeSignedIn") }
    /// Keeps the translation extension from reporting itself (negative Verify path).
    static var muteTranslationReport: Bool { d.bool(forKey: "ui.muteTranslationReport") }
    /// Closes the translation sheet 4 s after Verify: XCUITest cannot touch a
    /// sheet hosted by another process, and the user's close uses this binding.
    static var autoDismissVerify: Bool { d.bool(forKey: "ui.autoDismissVerify") }
    static var licenseState: LicenseState? {
        switch d.string(forKey: "ui.licenseState") {
        case "trial": return .trial(daysRemaining: 9)
        case "active": return .active(planName: "Pro", validatedAt: Date(), isOfflineGrace: false)
        case "expired": return .expired
        default: return nil
        }
    }
#else
    // Release builds ignore launch arguments entirely: no forced license
    // state, no prefilled text, no seeded history.
    static var tab: String? { nil }
    static var showPaywall: Bool { false }
    static var showSignIn: Bool { false }
    static var showSetup: Bool { false }
    static var showFeedback: Bool { false }
    static var sourceText: String? { nil }
    static var autoTranslate: Bool { false }
    static var seedHistory: Bool { false }
    static var previewPricing: PaywallView.Preview? { nil }
    static var setupState: String? { nil }
    static var fakeSignedIn: Bool { false }
    static var muteTranslationReport: Bool { false }
    static var autoDismissVerify: Bool { false }
    static var licenseState: LicenseState? { nil }
#endif
}
