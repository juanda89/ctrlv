import ControlVCore
import Foundation

/// Syncs data the extensions need (session token) into App Group UserDefaults.
/// Extensions (Share, Keyboard) run in separate containers and cannot read the
/// main app's encrypted AccountStore, so the token is mirrored here.
///
/// Note: App Group UserDefaults is not encrypted like AccountStore, but it IS
/// sandboxed to this app group. Session tokens are revocable server-side.
enum AppGroupBridge {
    private static let appGroup = "group.info.controlv.shared"
    private static let tokenKey = "iOSSessionToken"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    /// Call after sign-in, sign-out, and on app launch to keep extensions in sync.
    static func syncSessionToken(from licenseService: LicenseService) {
        if let token = licenseService.storedSessionToken, !token.isEmpty {
            defaults.set(token, forKey: tokenKey)
        } else {
            defaults.removeObject(forKey: tokenKey)
        }
    }
}
