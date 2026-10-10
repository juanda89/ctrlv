import Foundation

/// Links into the app (`controlv://`, registered in project.yml). The
/// extensions use them to send people to a screen only the app has.
public enum AppLink {
    public static let scheme = "controlv"
    /// Opens the paywall: the way out of a trial that ran out.
    public static let subscribe = URL(string: "controlv://subscribe")!

    public static func isSubscribe(_ url: URL) -> Bool {
        url.scheme?.lowercased() == scheme && url.host?.lowercased() == "subscribe"
    }
}
