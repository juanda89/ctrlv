import CryptoKit
import Foundation
import Security

public protocol AccountStoring {
    func read() -> StoredAccountRecord?
    func save(_ record: StoredAccountRecord)
    func delete()
}

public final class AccountStore: AccountStoring {
    private let fileName = "account.enc"
    private let saltFileName = "account.salt"
    private let directoryURL: URL

    /// `directoryURL` is injectable so tests run against a temporary folder
    /// instead of the real store. (The old tests hit the real path and called
    /// delete() in setUp/tearDown, which signed the developer out on every
    /// `swift test` run.)
    public init(directoryURL: URL? = nil) {
        self.directoryURL = directoryURL ?? Self.defaultDirectoryURL
    }

    public func read() -> StoredAccountRecord? {
        guard let encrypted = try? Data(contentsOf: fileURL),
              let sealed = try? AES.GCM.SealedBox(combined: encrypted) else {
            return nil
        }

        if let record = decode(sealed, using: symmetricKey) {
            return record
        }

        // Migration: records written before the key material was made stable
        // were sealed with a key derived from the network host name. If that
        // still matches, decrypt with it and immediately re-seal with the
        // stable key so the next network change can't sign the user out.
        if let record = decode(sealed, using: legacySymmetricKey) {
            save(record)
            return record
        }
        return nil
    }

    public func save(_ record: StoredAccountRecord) {
        guard let payload = try? JSONEncoder().encode(record),
              let sealed = try? AES.GCM.seal(payload, using: symmetricKey),
              let combined = sealed.combined else {
            return
        }

        ensureDirectoryExists()
        try? combined.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    public func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Keys

    /// Stable key: bundle ID + user name + a random per-install salt persisted
    /// next to the record. Nothing here changes across app updates, reboots,
    /// or network changes.
    private var symmetricKey: SymmetricKey {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.instanttranslator.app"
        let username = Self.userIdentity
        let salt = installSalt()
        var material = Data("\(bundleID)|\(username)|instanttranslator-account-v2|".utf8)
        material.append(salt)
        let digest = SHA256.hash(data: material)
        return SymmetricKey(data: Data(digest))
    }

    /// Pre-v2 derivation. `ProcessInfo.hostName` is the *network* host name,
    /// which changes with Wi-Fi/DNS — so the key silently changed and the
    /// stored session became undecryptable, surfacing as "expired". Kept only
    /// to migrate existing records in `read()`.
    var legacySymmetricKey: SymmetricKey {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.instanttranslator.app"
        let username = Self.userIdentity
        let hostname = ProcessInfo.processInfo.hostName
        let material = "\(bundleID)|\(username)|\(hostname)|instanttranslator-account-v1"
        let digest = SHA256.hash(data: Data(material.utf8))
        return SymmetricKey(data: Data(digest))
    }

    /// macOS keys include the login name; iOS has no such API and the app
    /// sandbox already scopes the file to one user, so a constant is used.
    private static var userIdentity: String {
        #if os(macOS)
        return ProcessInfo.processInfo.userName
        #else
        return "ios"
        #endif
    }

    /// Random 32-byte salt created once per install and reused forever.
    private func installSalt() -> Data {
        if let existing = try? Data(contentsOf: saltFileURL), existing.count == 32 {
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let salt = Data(bytes)
        ensureDirectoryExists()
        try? salt.write(to: saltFileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: saltFileURL.path)
        return salt
    }

    // MARK: - Paths

    private static var defaultDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let base = appSupport ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent(Constants.appName, isDirectory: true)
    }

    var fileURL: URL {
        directoryURL.appendingPathComponent(fileName, isDirectory: false)
    }

    private var saltFileURL: URL {
        directoryURL.appendingPathComponent(saltFileName, isDirectory: false)
    }

    private func ensureDirectoryExists() {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func decode(_ sealed: AES.GCM.SealedBox, using key: SymmetricKey) -> StoredAccountRecord? {
        guard let decrypted = try? AES.GCM.open(sealed, using: key),
              let record = try? JSONDecoder().decode(StoredAccountRecord.self, from: decrypted) else {
            return nil
        }
        return record
    }
}
