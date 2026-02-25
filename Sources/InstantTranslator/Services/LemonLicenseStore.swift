import CryptoKit
import Foundation

protocol LemonLicenseStoring {
    func read() -> StoredLicenseRecord?
    func save(_ record: StoredLicenseRecord)
    func delete()
}

final class LemonLicenseStore: LemonLicenseStoring {
    private let fileName = "license_state.enc"

    func read() -> StoredLicenseRecord? {
        guard let encrypted = try? Data(contentsOf: fileURL),
              let sealed = try? AES.GCM.SealedBox(combined: encrypted),
              let decrypted = try? AES.GCM.open(sealed, using: symmetricKey),
              let record = try? JSONDecoder().decode(StoredLicenseRecord.self, from: decrypted) else {
            return nil
        }
        return record
    }

    func save(_ record: StoredLicenseRecord) {
        guard let payload = try? JSONEncoder().encode(record),
              let sealed = try? AES.GCM.seal(payload, using: symmetricKey),
              let combined = sealed.combined else {
            return
        }

        ensureDirectoryExists()
        try? combined.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let base = appSupport ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent(Constants.appName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    private var symmetricKey: SymmetricKey {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.instanttranslator.app"
        let material = "\(bundleID)|\(NSUserName())|\(Host.current().name ?? "unknown")|instanttranslator-license-v1"
        let digest = SHA256.hash(data: Data(material.utf8))
        return SymmetricKey(data: Data(digest))
    }

    private func ensureDirectoryExists() {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
