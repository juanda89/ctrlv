import Foundation

final class DeviceIdentityStore {
    private let userDefaults: UserDefaults
    private let installIDKey = "ctrlvInstallID"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func currentInstallID() -> String {
        if let existing = userDefaults.string(forKey: installIDKey), !existing.isEmpty {
            return existing
        }

        let installID = UUID().uuidString.lowercased()
        userDefaults.set(installID, forKey: installIDKey)
        return installID
    }
}
