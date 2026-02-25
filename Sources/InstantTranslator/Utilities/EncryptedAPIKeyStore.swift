import CryptoKit
import Foundation

enum EncryptedAPIKeyStore {
    private static let fileName = "api_key.enc"

    static func save(_ value: String) {
        guard !value.isEmpty else {
            delete()
            return
        }
        guard let plaintext = value.data(using: .utf8) else { return }
        guard let sealed = try? AES.GCM.seal(plaintext, using: symmetricKey),
              let combined = sealed.combined else { return }

        ensureDirectoryExists()
        try? combined.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    static func read() -> String? {
        guard let encrypted = try? Data(contentsOf: fileURL),
              let sealed = try? AES.GCM.SealedBox(combined: encrypted),
              let decrypted = try? AES.GCM.open(sealed, using: symmetricKey) else {
            return nil
        }
        return String(data: decrypted, encoding: .utf8)
    }

    static func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let base = appSupport ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent(Constants.appName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    private static var symmetricKey: SymmetricKey {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.instanttranslator.app"
        let material = "\(bundleID)|\(NSUserName())|\(Host.current().name ?? "unknown")|instanttranslator-api-key-v1"
        let digest = SHA256.hash(data: Data(material.utf8))
        return SymmetricKey(data: Data(digest))
    }

    private static func ensureDirectoryExists() {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
