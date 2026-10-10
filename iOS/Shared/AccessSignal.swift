import Foundation

/// "Pro just started working on this install." The app stamps it when its
/// plan turns active or the server accepts a purchase. iOS keeps a translation
/// sheet up while people go subscribe in the app, so a sheet left on its
/// trial-ended card retries once it sees a newer stamp: coming back translates.
public enum AccessSignal {
    private static let key = "access.unlockedAt"
    /// A fresh instance per access: the writer is another process.
    private static var defaults: UserDefaults { UserDefaults(suiteName: SetupState.appGroup) ?? .standard }

    public static func stamp() {
        defaults.set(Date(), forKey: key)
    }

    public static var lastStamp: Date? {
        defaults.object(forKey: key) as? Date
    }
}
