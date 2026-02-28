import AppKit
import Foundation

@MainActor
@Observable
final class LicenseService {
    private(set) var state: LicenseState = .checking {
        didSet {
            if state != oldValue {
                TelemetryService.trackLicenseState(state)
            }
        }
    }
    private(set) var isLoading = false
    private(set) var lastError: String?

    var storedLicenseKey: String? {
        store.read()?.licenseKey
    }

    private let installDateKey = "installDate"
    private let legacyAuthEmailKey = "subscriptionAuthEmail"
    private let legacySessionTokenKey = "subscriptionSessionToken"
    private let trialDays = 14
    private let periodicRevalidationSeconds: TimeInterval = 12 * 60 * 60
    private let translationRevalidationSeconds: TimeInterval = 24 * 60 * 60
    private let offlineGraceSeconds: TimeInterval = 30 * 24 * 60 * 60

    private let client: LemonLicenseClientProtocol
    private let store: LemonLicenseStoring
    private let userDefaults: UserDefaults
    private let now: () -> Date
    private let openURLHandler: (URL) -> Void
    private let instanceName: String
    private let startBackgroundTasks: Bool

    private var revalidationTask: Task<Void, Never>?

    init(
        client: LemonLicenseClientProtocol = LemonLicenseClient(),
        store: LemonLicenseStoring = LemonLicenseStore(),
        userDefaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        openURLHandler: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
        instanceName: String = Host.current().localizedName ?? "macOS",
        startBackgroundTasks: Bool = true
    ) {
        self.client = client
        self.store = store
        self.userDefaults = userDefaults
        self.now = now
        self.openURLHandler = openURLHandler
        self.instanceName = instanceName
        self.startBackgroundTasks = startBackgroundTasks

        clearLegacySessionKeys()
        loadState()
        if startBackgroundTasks {
            startPeriodicRevalidation()
        }

        if startBackgroundTasks, store.read() != nil {
            Task { [weak self] in
                await self?.refreshLicenseStatus(forceNetwork: false)
            }
        }
    }

    func loadState() {
        lastError = nil

        guard let record = store.read(), !record.licenseKey.isEmpty else {
            state = localTrialOrExpiredState()
            return
        }

        if let lastValidatedAt = record.lastValidatedAt,
           record.lastKnownStatus?.lowercased() == "active",
           now().timeIntervalSince(lastValidatedAt) <= offlineGraceSeconds {
            state = .active(planName: record.lastPlanName, validatedAt: lastValidatedAt, isOfflineGrace: true)
            return
        }

        let fallback = localTrialOrExpiredState()
        state = fallback.canTranslate ? fallback : .invalid(reason: "License requires online validation")
    }

    func submitLicenseKey(_ key: String) async -> Bool {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty else {
            lastError = "License key is required"
            return false
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let activation = try await client.activate(
                licenseKey: normalizedKey,
                instanceName: instanceName
            )

            var record = StoredLicenseRecord(
                licenseKey: normalizedKey,
                instanceID: activation.instanceID,
                lastValidatedAt: nil,
                lastKnownStatus: nil,
                lastPlanName: activation.planName
            )

            let validation = try await client.validate(
                licenseKey: normalizedKey,
                instanceID: activation.instanceID
            )

            record.instanceID = validation.instanceID ?? record.instanceID
            record.lastValidatedAt = now()
            record.lastKnownStatus = validation.status.rawValue
            record.lastPlanName = validation.planName ?? record.lastPlanName
            store.save(record)

            if validation.isValid && validation.status == .active {
                state = .active(
                    planName: record.lastPlanName,
                    validatedAt: record.lastValidatedAt ?? now(),
                    isOfflineGrace: false
                )
                lastError = nil
                return true
            }

            let reason = validation.reason ?? validation.status.rawValue
            applyInvalidOrTrialFallback(reason: reason)
            return false
        } catch {
            lastError = error.localizedDescription
            applyInvalidOrTrialFallback(reason: "Could not validate license")
            return false
        }
    }

    func refreshLicenseStatus(forceNetwork: Bool = false) async {
        guard !isLoading else { return }
        guard var record = store.read(), !record.licenseKey.isEmpty else {
            state = localTrialOrExpiredState()
            return
        }

        let shouldSkipNetwork = !forceNetwork &&
            record.lastKnownStatus?.lowercased() == "active" &&
            isWithinRevalidationWindow(record.lastValidatedAt)

        if shouldSkipNetwork {
            if let validatedAt = record.lastValidatedAt {
                state = .active(
                    planName: record.lastPlanName,
                    validatedAt: validatedAt,
                    isOfflineGrace: false
                )
            }
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let validation = try await client.validate(
                licenseKey: record.licenseKey,
                instanceID: record.instanceID
            )

            record.instanceID = validation.instanceID ?? record.instanceID
            record.lastValidatedAt = now()
            record.lastKnownStatus = validation.status.rawValue
            record.lastPlanName = validation.planName ?? record.lastPlanName
            store.save(record)

            if validation.isValid && validation.status == .active {
                state = .active(
                    planName: record.lastPlanName,
                    validatedAt: record.lastValidatedAt ?? now(),
                    isOfflineGrace: false
                )
                lastError = nil
                return
            }

            let reason = validation.reason ?? validation.status.rawValue
            applyInvalidOrTrialFallback(reason: reason)
        } catch {
            lastError = error.localizedDescription

            if let lastValidatedAt = record.lastValidatedAt,
               record.lastKnownStatus?.lowercased() == "active",
               now().timeIntervalSince(lastValidatedAt) <= offlineGraceSeconds {
                state = .active(
                    planName: record.lastPlanName,
                    validatedAt: lastValidatedAt,
                    isOfflineGrace: true
                )
                return
            }

            let fallback = localTrialOrExpiredState()
            state = fallback.canTranslate ? fallback : .invalid(reason: "Could not validate license while offline")
        }
    }

    func deactivateCurrentLicense() async -> Bool {
        guard let record = store.read(), !record.licenseKey.isEmpty else {
            clearStoredLicense()
            return true
        }

        guard let instanceID = record.instanceID, !instanceID.isEmpty else {
            clearStoredLicense()
            return true
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let success = try await client.deactivate(
                licenseKey: record.licenseKey,
                instanceID: instanceID
            )
            if success {
                clearStoredLicense()
            } else {
                lastError = "Could not deactivate this device"
            }
            return success
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func clearStoredLicense() {
        store.delete()
        lastError = nil
        loadState()
    }

    func openUpgrade() {
        openURL(Constants.lemonCheckoutURL)
    }

    func openManageSubscription() {
        openURL(Constants.lemonPortalURL)
    }

    // MARK: - Private

    private func startPeriodicRevalidation() {
        revalidationTask?.cancel()
        revalidationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                try? await Task.sleep(nanoseconds: UInt64(self.periodicRevalidationSeconds * 1_000_000_000))
                if Task.isCancelled { break }
                await self.refreshLicenseStatus(forceNetwork: true)
            }
        }
    }

    private func clearLegacySessionKeys() {
        userDefaults.removeObject(forKey: legacyAuthEmailKey)
        userDefaults.removeObject(forKey: legacySessionTokenKey)
    }

    private func isWithinRevalidationWindow(_ date: Date?) -> Bool {
        guard let date else { return false }
        return now().timeIntervalSince(date) < translationRevalidationSeconds
    }

    private func localTrialOrExpiredState() -> LicenseState {
        let installDate = storedInstallDate()
        let daysSinceInstall = Calendar.current.dateComponents([.day], from: installDate, to: now()).day ?? 0
        let remaining = max(0, trialDays - daysSinceInstall)
        return remaining > 0 ? .trial(daysRemaining: remaining) : .expired
    }

    private func storedInstallDate() -> Date {
        if let saved = userDefaults.object(forKey: installDateKey) as? Date {
            return saved
        }

        let createdAt = now()
        userDefaults.set(createdAt, forKey: installDateKey)
        return createdAt
    }

    private func applyInvalidOrTrialFallback(reason: String) {
        let fallback = localTrialOrExpiredState()
        state = fallback.canTranslate ? fallback : .invalid(reason: reason)
        if !fallback.canTranslate {
            lastError = reason
        }
    }

    private func openURL(_ url: URL?) {
        guard let url else { return }
        openURLHandler(url)
    }
}
