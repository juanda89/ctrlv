import CryptoKit
@testable import ControlVCore
import Foundation
import XCTest
@testable import InstantTranslator

/// All tests run against a throwaway temp directory. The previous version of
/// this suite used the real store path and called delete() in setUp/tearDown,
/// which signed the developer out on every `swift test` run.
final class AccountStoreTests: XCTestCase {
    private var directory: URL!
    private var store: AccountStore!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("account-store-tests-\(UUID().uuidString)", isDirectory: true)
        store = AccountStore(directoryURL: directory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        store = nil
        directory = nil
        super.tearDown()
    }

    func test_save_and_read_roundTripsRecord() {
        let record = StoredAccountRecord(
            email: "user@example.com",
            sessionToken: "tok-abc-123",
            subscriptionStatus: "active",
            planName: "Pro",
            lastValidatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        store.save(record)
        let loaded = store.read()

        XCTAssertEqual(loaded?.email, "user@example.com")
        XCTAssertEqual(loaded?.sessionToken, "tok-abc-123")
        XCTAssertEqual(loaded?.subscriptionStatus, "active")
        XCTAssertEqual(loaded?.planName, "Pro")
        XCTAssertEqual(loaded?.lastValidatedAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func test_read_returnsNil_whenNothingStored() {
        XCTAssertNil(store.read())
    }

    func test_delete_clearsRecord() {
        store.save(makeRecord(token: "tok"))
        XCTAssertNotNil(store.read())

        store.delete()
        XCTAssertNil(store.read())
    }

    func test_save_overwritesPreviousRecord() {
        store.save(StoredAccountRecord(
            email: "first@example.com",
            sessionToken: "first-token",
            subscriptionStatus: nil,
            planName: nil,
            lastValidatedAt: nil
        ))
        store.save(StoredAccountRecord(
            email: "second@example.com",
            sessionToken: "second-token",
            subscriptionStatus: "active",
            planName: "Pro",
            lastValidatedAt: nil
        ))

        let loaded = store.read()
        XCTAssertEqual(loaded?.email, "second@example.com")
        XCTAssertEqual(loaded?.sessionToken, "second-token")
    }

    func test_storedFile_isReadOnlyByOwner() throws {
        store.save(makeRecord(token: "tok"))

        let attrs = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
        let permissions = attrs[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.int16Value, 0o600)
    }

    // MARK: - Key stability (regression: session "expired" after network change / update)

    func test_read_worksFromFreshInstance_usingPersistedSalt() {
        store.save(makeRecord(token: "persisted-token"))

        // A new instance (app relaunch, e.g. after a Sparkle update) must
        // derive the exact same key from the salt file on disk.
        let relaunched = AccountStore(directoryURL: directory)
        XCTAssertEqual(relaunched.read()?.sessionToken, "persisted-token")
    }

    func test_read_migratesRecordSealedWithLegacyHostnameKey() throws {
        // Simulate a record written by a pre-v2 build: sealed with the key
        // derived from the network host name.
        let record = makeRecord(token: "legacy-token")
        let payload = try JSONEncoder().encode(record)
        let sealed = try AES.GCM.seal(payload, using: store.legacySymmetricKey)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try XCTUnwrap(sealed.combined).write(to: store.fileURL, options: .atomic)

        // First read decrypts via the legacy key and re-seals with the stable key.
        XCTAssertEqual(store.read()?.sessionToken, "legacy-token")

        // After migration the file must no longer depend on the legacy key:
        // it must open with the stable key alone.
        let migrated = try Data(contentsOf: store.fileURL)
        let box = try AES.GCM.SealedBox(combined: migrated)
        XCTAssertNil(try? AES.GCM.open(box, using: store.legacySymmetricKey),
                     "Record should have been re-sealed with the stable key")
        XCTAssertEqual(AccountStore(directoryURL: directory).read()?.sessionToken, "legacy-token")
    }

    func test_read_returnsNil_whenFileIsCorrupt() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-a-sealed-box".utf8).write(to: store.fileURL)

        XCTAssertNil(store.read())
    }

    // MARK: - Helpers

    private func makeRecord(token: String) -> StoredAccountRecord {
        StoredAccountRecord(
            email: "u@x.com",
            sessionToken: token,
            subscriptionStatus: nil,
            planName: nil,
            lastValidatedAt: nil
        )
    }
}
