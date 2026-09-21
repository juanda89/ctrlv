import ControlVCore
import KeyboardKit
import SwiftUI
import TranslationUIProvider
import UIKit
import XCTest

/// Stand-in for the system-provided context (iOS 18.4+ default translation app).
@Observable
final class MockTranslationContext: TranslationUIProviderContext {
    var inputText: AttributedString?
    var allowsReplacement: Bool
    init(text: String, allowsReplacement: Bool) {
        inputText = AttributedString(text)
        self.allowsReplacement = allowsReplacement
    }
    func finish(translation: AttributedString?) {}
    func expandSheet() {}
}

/// Renders the keyboard panel and the share sheet — UIs that can't be driven
/// from the command line — to PNGs for visual review.
///
///     TEST_RUNNER_SNAPSHOT_DIR=/abs/dir xcodebuild test -scheme Control-V \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:'Control-V Snapshots'
///
/// Without SNAPSHOT_DIR the images land in the host app's tmp directory.
final class ExtensionSnapshotTests: XCTestCase {
    private static let keyboardSize = CGSize(width: 402, height: ControlVKeyboardView.bandHeight + 4 * 54)
    private static let sheetSize = CGSize(width: 402, height: 620)
    // Measured behind the iOS 26 keyboard: (224, 226, 229) light, (27, 27, 29) dark.
    private static let lightKeyboard = UIColor(red: 224/255, green: 226/255, blue: 229/255, alpha: 1)
    private static let darkKeyboard = UIColor(red: 27/255, green: 27/255, blue: 29/255, alpha: 1)

    private var outputDir: URL {
        let path = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] ?? NSTemporaryDirectory()
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// A KeyboardKit keyboard configured like the extension's, with no controller.
    @MainActor
    private func makeKeyboard(language: KeyboardLanguage, dark: Bool) -> (Keyboard.State, Keyboard.Services) {
        let state = Keyboard.State()
        state.keyboardContext.colorScheme = dark ? .dark : .light
        state.keyboardContext.screenSize = CGSize(width: 402, height: 874)
        state.keyboardContext.setIsLiquidGlassEnabled(state.keyboardContext.isLiquidGlassAvailable)
        let services = Keyboard.Services(state: state)
        services.layoutService = ControlVLayoutService(language: language)
        return (state, services)
    }

    @MainActor
    func test_renderKeyboardPanel_allPhases() throws {
        let states: [(String, TranslateFlow.Phase, String?, Bool)] = [
            ("kb-idle", .idle, nil, false),
            ("kb-options", .idle, nil, true),
            ("kb-translating", .translating, nil, false),
            ("kb-done", .done, nil, false),
            ("kb-copied", .copiedFallback, nil, false),
            ("kb-error", .error, "Nothing to translate. Select text or type something first.", false),
        ]
        for (name, phase, message, options) in states {
            let (state, services) = makeKeyboard(language: .english, dark: false)
            let flow = TranslateFlow(hasFullAccess: true, actions: .noop)
            flow.applyPreview(phase: phase, errorMessage: message, showsOptions: options)
            let view = ControlVKeyboardView(services: services, state: state, flow: flow)
            try snapshot(view, size: Self.keyboardSize, name: name, background: Self.lightKeyboard, ignoresSafeArea: true)
        }
        let (state, services) = makeKeyboard(language: .english, dark: true)
        let flow = TranslateFlow(hasFullAccess: true, actions: .noop)
        try snapshot(ControlVKeyboardView(services: services, state: state, flow: flow), size: Self.keyboardSize, name: "kb-idle-dark", dark: true, background: Self.darkKeyboard, ignoresSafeArea: true)
    }

    @MainActor
    func test_renderShareSheet_states() throws {
        let source = "Hola, ¿cómo estás? Quería confirmar la reunión de mañana a las 10 y saber si necesitas algo más de mi parte."
        let translated = "Hi, how are you? I wanted to confirm our meeting tomorrow at 10 and see if you need anything else from me."
        try snapshot(ShareResultView(sourceText: source, onDone: {}, onCopy: { _ in }, preview: .loading), size: Self.sheetSize, name: "share-loading", background: .systemBackground)
        try snapshot(ShareResultView(sourceText: source, onDone: {}, onCopy: { _ in }, preview: .done(translated)), size: Self.sheetSize, name: "share-done", background: .systemBackground)
        try snapshot(ShareResultView(sourceText: source, onDone: {}, onCopy: { _ in }, preview: .done(translated)), size: Self.sheetSize, name: "share-done-dark", dark: true, background: .systemBackground)
        try snapshot(ShareResultView(sourceText: source, onDone: {}, onCopy: { _ in }, preview: .failed("Daily limit reached. Upgrade to keep translating.")), size: Self.sheetSize, name: "share-error", background: .systemBackground)
        try snapshot(ShareResultView(sourceText: source, onDone: {}, onCopy: { _ in }, preview: .done(translated)), size: Self.sheetSize, name: "share-done-nosafearea", background: .systemBackground, ignoresSafeArea: true)
    }

    @MainActor
    func test_renderTranslationSheet_states() throws {
        let source = "Hola, ¿cómo estás? Quería confirmar la reunión de mañana a las 10 y saber si necesitas algo más de mi parte."
        let translated = "Hi, how are you? I wanted to confirm our meeting tomorrow at 10 and see if you need anything else from me."
        let size = CGSize(width: 402, height: 400)
        let editable = MockTranslationContext(text: source, allowsReplacement: true)
        let readOnly = MockTranslationContext(text: source, allowsReplacement: false)
        try snapshot(TranslationProviderView(context: editable, preview: .translating), size: size, name: "tr-translating", background: .systemBackground, ignoresSafeArea: true)
        try snapshot(TranslationProviderView(context: editable, preview: .done(translated)), size: size, name: "tr-done-replace", background: .systemBackground, ignoresSafeArea: true)
        try snapshot(TranslationProviderView(context: readOnly, preview: .done(translated)), size: size, name: "tr-done-readonly", background: .systemBackground, ignoresSafeArea: true)
        try snapshot(TranslationProviderView(context: editable, preview: .failed("Your free trial has ended. Open Control-V to subscribe.")), size: size, name: "tr-error", background: .systemBackground, ignoresSafeArea: true)
        try snapshot(TranslationProviderView(context: editable, preview: .done(translated)), size: size, name: "tr-done-dark", dark: true, background: .systemBackground, ignoresSafeArea: true)
    }

    /// The App Review screenshot for the subscription, and a design check of the
    /// paywall: `preview:` supplies the price StoreKit only serves when the app
    /// runs from the scheme's StoreKit configuration.
    @MainActor
    func test_renderPaywall_forAppReview() throws {
        let license = LicenseService(openURLHandler: { _ in }, startBackgroundTasks: false)
        license.applyDebugState(.trial(daysRemaining: 9))
        let subscriptions = StoreKitSubscriptionManager(licenseService: license)
        let paywall = PaywallView(preview: .init(priceText: "$4.99", trialDays: 14))
            .environment(license)
            .environment(subscriptions)
        try snapshot(paywall, size: CGSize(width: 402, height: 874), name: "paywall-review", background: .systemBackground)
        try snapshot(paywall, size: CGSize(width: 402, height: 874), name: "paywall-review-dark", dark: true, background: .systemBackground)
    }

    /// The Spanish layout must carry Ñ in the middle row; the simulator runs in
    /// English, so the language is injected rather than inferred here.
    @MainActor
    func test_renderKeyboardLayout_spanish() throws {
        for dark in [false, true] {
            let (state, services) = makeKeyboard(language: .spanish, dark: dark)
            let flow = TranslateFlow(hasFullAccess: true, actions: .noop)
            let view = ControlVKeyboardView(services: services, state: state, flow: flow)
            try snapshot(view, size: Self.keyboardSize, name: dark ? "kb-spanish-dark" : "kb-spanish", dark: dark, background: dark ? Self.darkKeyboard : Self.lightKeyboard, ignoresSafeArea: true)
        }
    }

    // MARK: - Rendering

    @MainActor
    private func snapshot<V: View>(_ view: V, size: CGSize, name: String, dark: Bool = false, background: UIColor, ignoresSafeArea: Bool = false) throws {
        // A window only renders when it belongs to the host app's scene;
        // without this drawHierarchy returns a blank image.
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.overrideUserInterfaceStyle = dark ? .dark : .light
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1)
        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = background
        // The keyboard sits above the home indicator with no status bar; the
        // test window is at the screen's top-left, so drop the inherited insets.
        if ignoresSafeArea { host.safeAreaRegions = [] }
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 3
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        // Warm-up pass: the first draw of a view that uses glass/material samples a
        // stale backdrop, which leaves a ghost of the content behind the card.
        _ = renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let url = outputDir.appendingPathComponent("\(name).png")
        try XCTUnwrap(image.pngData()).write(to: url)
        window.isHidden = true
        print("snapshot written: \(url.path)")
    }
}
