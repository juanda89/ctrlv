import StoreKitTest
import XCTest

/// Not a check. Keeps a local StoreKit session (Configuration.storekit) alive
/// so the app can be driven by hand in the simulator, for example to record
/// the App Review walkthrough: the paywall then shows the real product, trial
/// and price, and the purchase sheet works without App Store Connect. The app
/// is installed but not launched, so the recording can start from the home
/// screen. DEMO_MINUTES (default 30) sets how long the session lives:
///
///     xcodebuild test-without-building … \
///       -only-testing:'Control-V UITests/DemoRecordingUITests/test_demo_holdStoreKitSession'
final class DemoRecordingUITests: XCTestCase {
    func test_demo_holdStoreKitSession() throws {
        let session = try SKTestSession(configurationFileNamed: "Configuration")
        session.disableDialogs = false
        session.resetToDefaultState()
        session.clearTransactions()
        let minutes = Double(ProcessInfo.processInfo.environment["DEMO_MINUTES"] ?? "") ?? 30
        let deadline = Date().addingTimeInterval(minutes * 60)
        while Date() < deadline { sleep(5) }
    }
}
