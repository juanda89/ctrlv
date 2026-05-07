import ControlVCore
import Foundation
import XCTest
@testable import InstantTranslator

final class AccountStoreTests: XCTestCase {
    private var store: AccountStore!
    private let testFileName = "account.enc"

    override func setUp() {
        super.setUp()
        store = AccountStore()
        store.delete() // Ensure clean state
    }

    override func tearDown() {
        store.delete()
        store = nil
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
        let record = StoredAccountRecord(
            email: "u@x.com",
            sessionToken: "tok",
            subscriptionStatus: nil,
            planName: nil,
            lastValidatedAt: nil
        )
        store.save(record)
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
        let record = StoredAccountRecord(
            email: "u@x.com",
            sessionToken: "tok",
            subscriptionStatus: nil,
            planName: nil,
            lastValidatedAt: nil
        )
        store.save(record)

        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let fileURL = appSupport
            .appendingPathComponent(Constants.appName, isDirectory: true)
            .appendingPathComponent(testFileName, isDirectory: false)

        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let permissions = attrs[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.int16Value, 0o600)
    }
}
