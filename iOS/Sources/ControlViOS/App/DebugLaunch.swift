import ControlVCore
import Foundation

/// Launch arguments (NSUserDefaults argument domain) used for headless
/// screenshots and QA: `xcrun simctl launch <udid> info.controlv.ios -ui.tab account`.
/// Never set by real users; every value is optional.
enum DebugLaunch {
    private static let d = UserDefaults.standard
    static var tab: String? { d.string(forKey: "ui.tab") }
    static var showPaywall: Bool { d.bool(forKey: "ui.showPaywall") }
    static var showSignIn: Bool { d.bool(forKey: "ui.showSignIn") }
    static var showSetup: Bool { d.bool(forKey: "ui.showSetup") }
    static var showFeedback: Bool { d.bool(forKey: "ui.showFeedback") }
    static var sourceText: String? { d.string(forKey: "ui.sourceText") }
    static var autoTranslate: Bool { d.bool(forKey: "ui.autoTranslate") }
    static var seedHistory: Bool { d.bool(forKey: "ui.seedHistory") }
    static var licenseState: LicenseState? {
        switch d.string(forKey: "ui.licenseState") {
        case "trial": return .trial(daysRemaining: 9)
        case "active": return .active(planName: "Pro", validatedAt: Date(), isOfflineGrace: false)
        case "expired": return .expired
        default: return nil
        }
    }
}
