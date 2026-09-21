import Foundation

/// Which of the two "translate anywhere" paths the user has actually enabled.
///
/// What iOS lets an app find out, and what it does not:
/// - Enabled keyboards are listed in the global preferences (`AppleKeyboards`),
///   third-party ones by extension bundle id, so "added in Settings" can be
///   read from the app at any time, without the keyboard ever running.
/// - Full Access is only visible to the keyboard itself, and being the default
///   translation app is visible to nobody (`UIApplication.Category` only
///   covers the web browser). So each extension reports that it ran, and with
///   what, through two channels: a mark in the App Group, and a Darwin
///   notification the app turns into its own record. Two channels because a
///   keyboard without Full Access may be denied the shared container on some
///   systems (it was not on the iOS 26 simulator, but Apple documents it),
///   while the notification needs no entitlement at all.
/// - The setup screen offers a text field where both paths can be triggered
///   on the spot, so the status shown is always something observed.
public enum SetupState {
    public static let appGroup = "group.info.controlv.shared"
    public static let keyboardBundleID = "info.controlv.ios.keyboard"

    private static let keyboardSeenKey = "setup.keyboardSeenAt"
    private static let keyboardFullAccessKey = "setup.keyboardFullAccess"
    private static let translationSeenKey = "setup.translationProviderSeenAt"
    private static let shareSeenKey = "setup.shareSeenAt"
    /// Written by the app when a Darwin signal arrives (see `Signal`).
    private static let keyboardSignalKey = "setup.keyboardSignalAt"
    private static let keyboardSignalFullAccessKey = "setup.keyboardSignalFullAccess"
    private static let translationSignalKey = "setup.translationSignalAt"
    /// Builds 1–4 let the user confirm by hand ("It's on"), which is exactly
    /// how a wrong status got recorded. Only cleared now, never read.
    private static let legacyConfirmKeys = ["setup.translationProviderConfirmed", "setup.keyboardConfirmed"]

    /// A fresh instance per access: the app and the extensions are separate
    /// processes, and a cached one keeps serving values written before the
    /// extension ran.
    private static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    // MARK: - Reported by the extensions

    public static func markKeyboardActive(hasFullAccess: Bool) {
        let d = defaults
        d.set(Date(), forKey: keyboardSeenKey)
        d.set(hasFullAccess, forKey: keyboardFullAccessKey)
        Signal.post(hasFullAccess ? .keyboardFullAccess : .keyboardLimited)
    }

    public static func markTranslationProviderActive() {
        defaults.set(Date(), forKey: translationSeenKey)
        Signal.post(.translation)
    }

    public static func markShareActive() {
        defaults.set(Date(), forKey: shareSeenKey)
    }

    /// Cross-process, entitlement-free signals (Darwin notification center).
    /// They carry no payload, so each fact is its own name.
    public enum Signal: String, CaseIterable {
        case keyboardFullAccess = "info.controlv.setup.keyboard.full"
        case keyboardLimited = "info.controlv.setup.keyboard.limited"
        case translation = "info.controlv.setup.translation"

        static func post(_ signal: Signal) {
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                                 CFNotificationName(signal.rawValue as CFString), nil, nil, true)
        }
    }

    // MARK: - Received by the app

    /// Call once at launch. While the app runs, a signal from an extension is
    /// recorded in the App Group by the app itself and announced through
    /// `Notification.Name.controlVSetupChanged`.
    public static func startObservingSignals() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        for signal in Signal.allCases {
            CFNotificationCenterAddObserver(center, nil, { _, _, name, _, _ in
                guard let name, let signal = SetupState.Signal(rawValue: name.rawValue as String) else { return }
                SetupState.record(signal)
            }, signal.rawValue as CFString, nil, .deliverImmediately)
        }
    }

    static func record(_ signal: Signal) {
        let d = defaults
        switch signal {
        case .keyboardFullAccess, .keyboardLimited:
            d.set(Date(), forKey: keyboardSignalKey)
            d.set(signal == .keyboardFullAccess, forKey: keyboardSignalFullAccessKey)
        case .translation:
            d.set(Date(), forKey: translationSignalKey)
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .controlVSetupChanged, object: nil)
        }
    }

    // MARK: - Read by the app

    public enum KeyboardStatus: Equatable {
        /// Not in the list of enabled keyboards.
        case notAdded
        /// Enabled in Settings but never opened, so Full Access is unknown.
        case addedNotOpened
        /// Opened without Full Access: it can type, it cannot translate.
        case addedNoFullAccess
        /// Opened with Full Access: translates.
        case ready
    }

    public static var keyboardStatus: KeyboardStatus {
        let enabled = enabledKeyboards
        if let enabled, !enabled.contains(where: { $0.hasPrefix(keyboardBundleID) }) {
            // Removed in Settings; whatever ran before no longer counts.
            return .notAdded
        }
        guard let (_, fullAccess) = latestKeyboardReport else {
            return enabled == nil ? .notAdded : .addedNotOpened
        }
        return fullAccess ? .ready : .addedNoFullAccess
    }

    /// The most recent of the keyboard's own mark and the app's record of its
    /// signal, whichever channel got through.
    private static var latestKeyboardReport: (Date, Bool)? {
        let d = defaults
        let mark = (d.object(forKey: keyboardSeenKey) as? Date).map { ($0, d.bool(forKey: keyboardFullAccessKey)) }
        let signal = (d.object(forKey: keyboardSignalKey) as? Date).map { ($0, d.bool(forKey: keyboardSignalFullAccessKey)) }
        switch (mark, signal) {
        case (nil, nil): return nil
        case (let m?, nil): return m
        case (nil, let s?): return s
        case (let m?, let s?): return m.0 >= s.0 ? m : s
        }
    }

    /// The keyboards enabled in Settings, as iOS keeps them in the global
    /// preferences domain (part of the standard defaults search list). nil when
    /// the list cannot be read: a device always has at least one keyboard, so
    /// an empty list means "unreadable", not "none".
    static var enabledKeyboards: [String]? {
        var list = UserDefaults.standard.object(forKey: "AppleKeyboards") as? [String]
        if list == nil {
            list = CFPreferencesCopyAppValue("AppleKeyboards" as CFString, kCFPreferencesAnyApplication) as? [String]
        }
        guard let list, !list.isEmpty else { return nil }
        return list
    }

    public static var keyboardEnabledInSettings: Bool {
        enabledKeyboards?.contains { $0.hasPrefix(keyboardBundleID) } ?? false
    }

    /// Added *and* allowed to reach the network, which is what it needs to translate.
    public static var keyboardReady: Bool { keyboardStatus == .ready }

    /// Control-V has run as the system translation provider, which only
    /// happens once it is the default translation app.
    public static var translationProviderReady: Bool {
        let d = defaults
        return d.object(forKey: translationSeenKey) != nil || d.object(forKey: translationSignalKey) != nil
    }

    /// At least one path works, so the app is usable outside itself.
    public static var anyReady: Bool { keyboardReady || translationProviderReady }

    // MARK: - Debug / QA

    /// Pretend both paths are set up (screenshots, previews).
    public static func overrideForPreview(keyboard: Bool, translationProvider: Bool) {
        let d = defaults
        if keyboard {
            d.set(Date(), forKey: keyboardSeenKey)
            d.set(true, forKey: keyboardFullAccessKey)
        }
        if translationProvider { d.set(Date(), forKey: translationSeenKey) }
    }

    public static func resetForPreview() {
        let d = defaults
        ([keyboardSeenKey, keyboardFullAccessKey, translationSeenKey, shareSeenKey,
          keyboardSignalKey, keyboardSignalFullAccessKey, translationSignalKey] + legacyConfirmKeys)
            .forEach(d.removeObject(forKey:))
    }
}

public extension Notification.Name {
    /// Posted on the main thread when an extension reports itself (see
    /// `SetupState.startObservingSignals`) or the setup sheet finishes.
    static let controlVSetupChanged = Notification.Name("info.controlv.setupChanged")
}
