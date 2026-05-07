import Foundation
import XCTest
@testable import InstantTranslator

@MainActor
final class LicenseServiceTests: XCTestCase {

    // MARK: - Sign-in flow

    func test_requestMagicCode_setsPendingEmail_whenSucceeds() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = InMemoryAccountStore()
        let client = MockAuthClient()
        let (defaults, suiteName) = makeUserDefaults()
        defer { cleanup(defaults, suiteName: suiteName) }

        let service = LicenseService(
            client: client,
            store: store,
            userDefaults: defaults,
            now: { now },
            openURLHandler: { _ in },
            startBackgroundTasks: false
        )

        let ok = await service.requestMagicCode(email: " User@Example.com ")

        XCTAssertTrue(ok)
        XCTAssertEqual(service.pendingMagicCodeEmail, "user@example.com")
        XCTAssertEqual(client.requestedEmails, ["user@example.com"])
    }

    func test_requestMagicCode_rejectsInvalidEmail() async {
        let store = InMemoryAccountStore()
        let client = MockAuthClient()
        let (defaults, suiteName) = makeUserDefaults()
        defer { cleanup(defaults, suiteName: suiteName) }

        let service = LicenseService(
            client: client,
            store: store,
            userDefaults: defaults,
            openURLHandler: { _ in },
            startBackgroundTasks: false
        )

        let ok = await service.requestMagicCode(email: "not-an-email")

        XCTAssertFalse(ok)
        XCTAssertNil(service.pendingMagicCodeEmail)
        XCTAssertEqual(client.requestedEmails, [])
    }

    func test_verifyMagicCode_savesSessionAndChecksStatus_whenSucceeds() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = InMemoryAccountStore()
        let client = MockAuthClient()
        client.verifyResult = .success("token-xyz")
        client.statusResult = .success(SubscriptionStatus(
            status: .active,
            planName: "Pro",
            trialDaysRemaining: nil
        ))
        let (defaults, suiteName) = makeUserDefaults()
        defer { cleanup(defaults, suiteName: suiteName) }

        let service = LicenseService(
            client: client,
            store: store,
            userDefaults: defaults,
            now: { now },
            openURLHandler: { _ in },
            startBackgroundTasks: false
        )

        _ = await service.requestMagicCode(email: "user@example.com")
        let ok = await service.verifyMagicCode("123456")

        XCTAssertTrue(ok)
        XCTAssertNil(service.pendingMagicCodeEmail)
        let saved = store.read()
        XCTAssertEqual(saved?.sessionToken, "token-xyz")
        XCTAssertEqual(saved?.email, "user@example.com")

        guard case .active(let planName, _, _) = service.state else {
            return XCTFail("Expected active state")
        }
        XCTAssertEqual(planName, "Pro")
    }

    func test_verifyMagicCode_keepsTrialState_whenSubscriptionInactive() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = InMemoryAccountStore()
        let client = MockAuthClient()
        client.verifyResult = .success("token-xyz")
        client.statusResult = .success(SubscriptionStatus(
            status: .trial,
            planName: nil,
            trialDaysRemaining: 7
        ))
        let (defaults, suiteName) = makeUserDefaults(installDate: now)
        defer { cleanup(defaults, suiteName: suiteName) }

        let service = LicenseService(
            client: client,
            store: store,
            userDefaults: defaults,
            now: { now },
            openURLHandler: { _ in },
            startBackgroundTasks: false
        )

        _ = await service.requestMagicCode(email: "user@example.com")
        _ = await service.verifyMagicCode("123456")

        if case .trial = service.state {
            // expected
        } else {
            XCTFail("Expected trial state, got \(service.state)")
        }
    }

    // MARK: - canTranslate gating

    func test_canTranslate_isFalse_whenStateExpired() {
        XCTAssertFalse(LicenseState.expired.canTranslate)
        XCTAssertFalse(LicenseState.invalid(reason: "x").canTranslate)
        XCTAssertFalse(LicenseState.checking.canTranslate)
    }

    func test_canTranslate_isTrue_whenTrialOrActive() {
        XCTAssertTrue(LicenseState.trial(daysRemaining: 1).canTranslate)
        XCTAssertTrue(LicenseState.active(planName: "Pro", validatedAt: Date(), isOfflineGrace: false).canTranslate)
        XCTAssertTrue(LicenseState.active(planName: "Pro", validatedAt: Date(), isOfflineGrace: true).canTranslate)
    }

    // MARK: - Offline grace

    func test_loadState_usesOfflineGrace_whenLastValidationWithin30Days() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let validatedAt = now.addingTimeInterval(-15 * 24 * 60 * 60) // 15 days ago
        let store = InMemoryAccountStore()
        store.save(StoredAccountRecord(
            email: "user@example.com",
            sessionToken: "token-xyz",
            subscriptionStatus: "active",
            planName: "Pro",
            lastValidatedAt: validatedAt
        ))

        let client = MockAuthClient()
        let (defaults, suiteName) = makeUserDefaults()
        defer { cleanup(defaults, suiteName: suiteName) }

        let service = LicenseService(
            client: client,
            store: store,
            userDefaults: defaults,
            now: { now },
            openURLHandler: { _ in },
            startBackgroundTasks: false
        )

        guard case .active(_, _, let isOfflineGrace) = service.state else {
            return XCTFail("Expected active state, got \(service.state)")
        }
        XCTAssertTrue(isOfflineGrace)
    }

    func test_loadState_fallsBackToTrial_whenLastValidationOver30Days() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let validatedAt = now.addingTimeInterval(-31 * 24 * 60 * 60)
        let store = InMemoryAccountStore()
        store.save(StoredAccountRecord(
            email: "user@example.com",
            sessionToken: "token-xyz",
            subscriptionStatus: "active",
            planName: "Pro",
            lastValidatedAt: validatedAt
        ))

        let client = MockAuthClient()
        let (defaults, suiteName) = makeUserDefaults(installDate: now)
        defer { cleanup(defaults, suiteName: suiteName) }

        let service = LicenseService(
            client: client,
            store: store,
            userDefaults: defaults,
            now: { now },
            openURLHandler: { _ in },
            startBackgroundTasks: false
        )

        if case .trial = service.state {
            // expected
        } else {
            XCTFail("Expected trial fallback, got \(service.state)")
        }
    }

    // MARK: - Sign out

    func test_signOut_clearsStoreAndPendingState() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = InMemoryAccountStore()
        store.save(StoredAccountRecord(
            email: "user@example.com",
            sessionToken: "token",
            subscriptionStatus: "active",
            planName: "Pro",
            lastValidatedAt: now
        ))

        let client = MockAuthClient()
        let (defaults, suiteName) = makeUserDefaults(installDate: now)
        defer { cleanup(defaults, suiteName: suiteName) }

        let service = LicenseService(
            client: client,
            store: store,
            userDefaults: defaults,
            now: { now },
            openURLHandler: { _ in },
            startBackgroundTasks: false
        )

        service.signOut()

        XCTAssertNil(store.read())
        XCTAssertNil(service.pendingMagicCodeEmail)
        XCTAssertFalse(service.isSignedIn)
    }

    // MARK: - openUpgrade / openManageSubscription

    func test_openUpgrade_callsCheckoutAndOpensURL() async {
        var openedURL: URL?
        let store = InMemoryAccountStore()
        store.save(StoredAccountRecord(
            email: "u@x.com", sessionToken: "tok", subscriptionStatus: nil,
            planName: nil, lastValidatedAt: nil
        ))
        let client = MockAuthClient()
        client.checkoutURL = URL(string: "https://checkout.stripe.com/c/pay/test")!
        let (defaults, suiteName) = makeUserDefaults()
        defer { cleanup(defaults, suiteName: suiteName) }

        let service = LicenseService(
            client: client,
            store: store,
            userDefaults: defaults,
            openURLHandler: { url in openedURL = url },
            startBackgroundTasks: false
        )

        await service.openUpgrade()

        XCTAssertEqual(openedURL?.absoluteString, "https://checkout.stripe.com/c/pay/test")
    }
}

// MARK: - Helpers

@MainActor
private func makeUserDefaults(installDate: Date? = nil) -> (UserDefaults, String) {
    let suiteName = "tests.licenseservice.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    if let installDate = installDate {
        defaults.set(installDate, forKey: "installDate")
    }
    return (defaults, suiteName)
}

@MainActor
private func cleanup(_ defaults: UserDefaults, suiteName: String) {
    defaults.removePersistentDomain(forName: suiteName)
}

// MARK: - Test doubles

@MainActor
final class InMemoryAccountStore: AccountStoring {
    private var record: StoredAccountRecord?

    func read() -> StoredAccountRecord? {
        record
    }

    func save(_ record: StoredAccountRecord) {
        self.record = record
    }

    func delete() {
        record = nil
    }
}

@MainActor
final class MockAuthClient: MagicCodeAuthClientProtocol {
    enum MockError: Error { case notConfigured }

    var requestedEmails: [String] = []
    var verifyResult: Result<String, Error> = .success("default-token")
    var statusResult: Result<SubscriptionStatus, Error> = .success(
        SubscriptionStatus(status: .trial, planName: nil, trialDaysRemaining: 14)
    )
    var checkoutURL: URL = URL(string: "https://example.com/checkout")!
    var portalURL: URL = URL(string: "https://example.com/portal")!

    func requestMagicCode(email: String) async throws {
        requestedEmails.append(email)
    }

    func verifyMagicCode(email: String, code: String) async throws -> String {
        switch verifyResult {
        case .success(let token): return token
        case .failure(let error): throw error
        }
    }

    func refreshSubscriptionStatus(token: String) async throws -> SubscriptionStatus {
        switch statusResult {
        case .success(let status): return status
        case .failure(let error): throw error
        }
    }

    func createCheckoutSession(token: String) async throws -> URL {
        checkoutURL
    }

    func createPortalSession(token: String) async throws -> URL {
        portalURL
    }
}
