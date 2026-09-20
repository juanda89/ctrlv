import Foundation

/// Which of the two "translate anywhere" paths the user has actually enabled.
///
/// iOS gives an app no way to ask "is my keyboard installed?" or "am I the
/// default translation app?", so each extension records the fact that it ran
/// (and, for the keyboard, whether Full Access is on) in the App Group. The
/// app reads those marks to show live status instead of asking the user to
/// confirm by hand.
public enum SetupState {
    public static let appGroup = "group.info.controlv.shared"

    private static let keyboardSeenKey = "setup.keyboardSeenAt"
    private static let keyboardFullAccessKey = "setup.keyboardFullAccess"
    private static let translationSeenKey = "setup.translationProviderSeenAt"
    private static let shareSeenKey = "setup.shareSeenAt"

    /// A fresh instance per access: the app and the extensions are separate
    /// processes, and a cached one keeps serving values written before the
    /// extension ran.
    private static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    // MARK: - Written by the extensions

    public static func markKeyboardActive(hasFullAccess: Bool) {
        let d = defaults
        d.set(Date(), forKey: keyboardSeenKey)
        d.set(hasFullAccess, forKey: keyboardFullAccessKey)
    }

    public static func markTranslationProviderActive() {
        defaults.set(Date(), forKey: translationSeenKey)
    }

    public static func markShareActive() {
        defaults.set(Date(), forKey: shareSeenKey)
    }

    // MARK: - Read by the app

    /// The keyboard has been added and opened at least once.
    public static var keyboardAdded: Bool { defaults.object(forKey: keyboardSeenKey) != nil }

    /// Added *and* allowed to reach the network, which is what it needs to translate.
    public static var keyboardReady: Bool { keyboardAdded && defaults.bool(forKey: keyboardFullAccessKey) }

    /// Control-V has been used as the system translation provider, which only
    /// happens once it is the default translation app.
    public static var translationProviderReady: Bool { defaults.object(forKey: translationSeenKey) != nil }

    /// At least one path works, so the app is usable outside itself.
    public static var anyReady: Bool { keyboardReady || translationProviderReady }

    /// Debug/QA: pretend both paths are set up (screenshots, previews).
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
        [keyboardSeenKey, keyboardFullAccessKey, translationSeenKey, shareSeenKey].forEach(d.removeObject(forKey:))
    }
}
