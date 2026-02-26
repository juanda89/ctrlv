import CryptoKit
import Foundation

enum EncryptedAPIKeyStore {
    private static let legacyFileName = "api_key.enc"

    static func save(_ value: String, for provider: ProviderType) {
        let targetURL = fileURL(for: provider)
        guard !value.isEmpty else {
            delete(for: provider)
            return
        }
        guard let plaintext = value.data(using: .utf8) else { return }
        guard let sealed = try? AES.GCM.seal(plaintext, using: symmetricKey),
              let combined = sealed.combined else { return }

        ensureDirectoryExists()
        try? combined.write(to: targetURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: targetURL.path)
    }

    static func read(for provider: ProviderType) -> String? {
        if provider == .claude {
            migrateLegacyClaudeKeyIfNeeded()
        }
        guard let encrypted = try? Data(contentsOf: fileURL(for: provider)),
              let sealed = try? AES.GCM.SealedBox(combined: encrypted),
              let decrypted = try? AES.GCM.open(sealed, using: symmetricKey) else {
            return nil
        }
        return String(data: decrypted, encoding: .utf8)
    }

    static func delete(for provider: ProviderType) {
        try? FileManager.default.removeItem(at: fileURL(for: provider))
    }

    private static func migrateLegacyClaudeKeyIfNeeded() {
        let targetURL = fileURL(for: .claude)
        guard !FileManager.default.fileExists(atPath: targetURL.path) else { return }

        let sourceURL = legacyFileURL
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return }

        ensureDirectoryExists()
        try? FileManager.default.copyItem(at: sourceURL, to: targetURL)
        try? FileManager.default.removeItem(at: sourceURL)
    }

    private static func fileURL(for provider: ProviderType) -> URL {
        let fileName = "api_key_\(provider.rawValue.lowercased()).enc"
        return baseDirectoryURL.appendingPathComponent(fileName, isDirectory: false)
    }

    private static var legacyFileURL: URL {
        baseDirectoryURL.appendingPathComponent(legacyFileName, isDirectory: false)
    }

    private static var baseDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let base = appSupport ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent(Constants.appName, isDirectory: true)
    }

    private static var symmetricKey: SymmetricKey {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.instanttranslator.app"
        let material = "\(bundleID)|\(NSUserName())|\(Host.current().name ?? "unknown")|instanttranslator-api-key-v1"
        let digest = SHA256.hash(data: Data(material.utf8))
        return SymmetricKey(data: Data(digest))
    }

    private static func ensureDirectoryExists() {
        let directory = baseDirectoryURL
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
