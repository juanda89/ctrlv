import Foundation
import XCTest
@testable import InstantTranslator

@MainActor
final class LicenseServiceTests: XCTestCase {

    func test_submitLicenseKey_setsActive_whenActivateAndValidateSucceed() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = InMemoryLicenseStore()
        let client = MockLemonLicenseClient()
        client.activationResult = LemonActivationResult(instanceID: "instance-1", planName: "Pro Plan")
        client.validationResult = LemonValidationResult(
            isValid: true,
            status: .active,
            planName: "Pro Plan",
            instanceID: "instance-1",
            reason: nil
        )
        let (defaults, suiteName) = makeUserDefaults()
        defer { cleanup(defaults, suiteName: suiteName) }

        let service = LicenseService(
            client: client,
            store: store,
            userDefaults: defaults,
            now: { now },
            openURLHandler: { _ in },
            instanceName: "Test Mac",
            startBackgroundTasks: false
        )

        let success = await service.submitLicenseKey("test-key")

        XCTAssertTrue(success)
        guard case .active(let planName, let validatedAt, let isOfflineGrace) = service.state else {
            return XCTFail("Expected active state")
        }
        XCTAssertEqual(planName, "Pro Plan")
        XCTAssertEqual(validatedAt, now)
        XCTAssertFalse(isOfflineGrace)
        XCTAssertEqual(store.record?.instanceID, "instance-1")
    }

    func test_refreshLicenseStatus_fallsBackToTrial_whenInvalidAndTrialRemaining() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let installDate = now.addingTimeInterval(-1 * 24 * 60 * 60)
        let store = InMemoryLicenseStore(
            record: StoredLicenseRecord(
                licenseKey: "test-key",
                instanceID: "instance-1",
                lastValidatedAt: now.addingTimeInterval(-2 * 24 * 60 * 60),
                lastKnownStatus: "active",
                lastPlanName: "Pro Plan"
            )
        )
        let client = MockLemonLicenseClient()
        client.validationResult = LemonValidationResult(
            isValid: false,
            status: .expired,
            planName: nil,
            instanceID: "instance-1",
            reason: "License expired"
        )
        let (defaults, suiteName) = makeUserDefaults()
        defaults.set(installDate, forKey: "installDate")
        defer { cleanup(defaults, suiteName: suiteName) }

        let service = LicenseService(
            client: client,
            store: store,
            userDefaults: defaults,
            now: { now },
            openURLHandler: { _ in },
            startBackgroundTasks: false
        )

        await service.refreshLicenseStatus(forceNetwork: true)

        guard case .trial(let daysRemaining) = service.state else {
            return XCTFail("Expected trial fallback")
        }
        XCTAssertEqual(daysRemaining, 13)
    }

    func test_refreshLicenseStatus_blocks_whenInvalidAndTrialExpired() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let installDate = now.addingTimeInterval(-20 * 24 * 60 * 60)
        let store = InMemoryLicenseStore(
            record: StoredLicenseRecord(
                licenseKey: "test-key",
                instanceID: "instance-1",
                lastValidatedAt: now.addingTimeInterval(-2 * 24 * 60 * 60),
                lastKnownStatus: "active",
                lastPlanName: "Pro Plan"
            )
        )
        let client = MockLemonLicenseClient()
        client.validationResult = LemonValidationResult(
            isValid: false,
            status: .canceled,
            planName: nil,
            instanceID: "instance-1",
            reason: "Subscription canceled"
        )
        let (defaults, suiteName) = makeUserDefaults()
        defaults.set(installDate, forKey: "installDate")
        defer { cleanup(defaults, suiteName: suiteName) }

        let service = LicenseService(
            client: client,
            store: store,
            userDefaults: defaults,
            now: { now },
            openURLHandler: { _ in },
            startBackgroundTasks: false
        )

        await service.refreshLicenseStatus(forceNetwork: true)

        guard case .invalid(let reason) = service.state else {
            return XCTFail("Expected invalid state")
        }
        XCTAssertTrue(reason.contains("Subscription canceled"))
        XCTAssertFalse(service.state.canTranslate)
    }

    func test_refreshLicenseStatus_keepsActiveOfflineGrace_whenNetworkFailsWithin30Days() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let installDate = now.addingTimeInterval(-40 * 24 * 60 * 60)
        let store = InMemoryLicenseStore(
            record: StoredLicenseRecord(
                licenseKey: "test-key",
                instanceID: "instance-1",
                lastValidatedAt: now.addingTimeInterval(-10 * 24 * 60 * 60),
                lastKnownStatus: "active",
                lastPlanName: "Pro Plan"
            )
        )
        let client = MockLemonLicenseClient()
        client.validationError = URLError(.notConnectedToInternet)
        let (defaults, suiteName) = makeUserDefaults()
        defaults.set(installDate, forKey: "installDate")
        defer { cleanup(defaults, suiteName: suiteName) }

        let service = LicenseService(
            client: client,
            store: store,
            userDefaults: defaults,
            now: { now },
            openURLHandler: { _ in },
            startBackgroundTasks: false
        )

        await service.refreshLicenseStatus(forceNetwork: true)

        guard case .active(_, let validatedAt, let isOfflineGrace) = service.state else {
            return XCTFail("Expected offline grace active state")
        }
        XCTAssertEqual(validatedAt, now.addingTimeInterval(-10 * 24 * 60 * 60))
        XCTAssertTrue(isOfflineGrace)
    }

    func test_refreshLicenseStatus_expiresOfflineGrace_after30Days() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let installDate = now.addingTimeInterval(-40 * 24 * 60 * 60)
        let store = InMemoryLicenseStore(
            record: StoredLicenseRecord(
                licenseKey: "test-key",
                instanceID: "instance-1",
                lastValidatedAt: now.addingTimeInterval(-31 * 24 * 60 * 60),
                lastKnownStatus: "active",
                lastPlanName: "Pro Plan"
            )
        )
        let client = MockLemonLicenseClient()
        client.validationError = URLError(.notConnectedToInternet)
        let (defaults, suiteName) = makeUserDefaults()
        defaults.set(installDate, forKey: "installDate")
        defer { cleanup(defaults, suiteName: suiteName) }

        let service = LicenseService(
            client: client,
            store: store,
            userDefaults: defaults,
            now: { now },
            openURLHandler: { _ in },
            startBackgroundTasks: false
        )

        await service.refreshLicenseStatus(forceNetwork: true)

        guard case .invalid = service.state else {
            return XCTFail("Expected invalid after grace expiry")
        }
        XCTAssertFalse(service.state.canTranslate)
    }

    func test_deactivateCurrentLicense_clearsStoredState_whenSuccess() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let installDate = now.addingTimeInterval(-2 * 24 * 60 * 60)
        let store = InMemoryLicenseStore(
            record: StoredLicenseRecord(
                licenseKey: "test-key",
                instanceID: "instance-1",
                lastValidatedAt: now,
                lastKnownStatus: "active",
                lastPlanName: "Pro Plan"
            )
        )
        let client = MockLemonLicenseClient()
        client.deactivateResult = true
        let (defaults, suiteName) = makeUserDefaults()
        defaults.set(installDate, forKey: "installDate")
        defer { cleanup(defaults, suiteName: suiteName) }

        let service = LicenseService(
            client: client,
            store: store,
            userDefaults: defaults,
            now: { now },
            openURLHandler: { _ in },
            startBackgroundTasks: false
        )

        let success = await service.deactivateCurrentLicense()

        XCTAssertTrue(success)
        XCTAssertNil(store.record)
        guard case .trial(let daysRemaining) = service.state else {
            return XCTFail("Expected trial after clearing stored license")
        }
        XCTAssertEqual(daysRemaining, 12)
    }

    // MARK: - Helpers

    private func makeUserDefaults() -> (UserDefaults, String) {
        let suiteName = "LicenseServiceTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    private func cleanup(_ defaults: UserDefaults, suiteName: String) {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private final class InMemoryLicenseStore: LemonLicenseStoring {
    var record: StoredLicenseRecord?

    init(record: StoredLicenseRecord? = nil) {
        self.record = record
    }

    func read() -> StoredLicenseRecord? {
        record
    }

    func save(_ record: StoredLicenseRecord) {
        self.record = record
    }

    func delete() {
        record = nil
    }
}

private final class MockLemonLicenseClient: LemonLicenseClientProtocol {
    var activationResult = LemonActivationResult(instanceID: "instance-default", planName: nil)
    var validationResult = LemonValidationResult(
        isValid: true,
        status: .active,
        planName: nil,
        instanceID: "instance-default",
        reason: nil
    )
    var deactivateResult = true
    var validationError: Error?

    func activate(licenseKey: String, instanceName: String) async throws -> LemonActivationResult {
        activationResult
    }

    func validate(licenseKey: String, instanceID: String?) async throws -> LemonValidationResult {
        if let validationError {
            throw validationError
        }
        return validationResult
    }

    func deactivate(licenseKey: String, instanceID: String) async throws -> Bool {
        deactivateResult
    }
}
