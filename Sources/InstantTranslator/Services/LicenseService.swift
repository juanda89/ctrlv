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

    /// Authentication progress flag for the sign-in flow.
    private(set) var pendingMagicCodeEmail: String?

    var storedSessionToken: String? {
        store.read()?.sessionToken
    }

    var storedEmail: String? {
        store.read()?.email
    }

    var isSignedIn: Bool {
        guard let record = store.read() else { return false }
        return !record.sessionToken.isEmpty
    }

    private let installDateKey = "installDate"
    private let legacyLemonStoreFile = "license_state.enc"
    private let legacyAuthEmailKey = "subscriptionAuthEmail"
    private let legacySessionTokenKey = "subscriptionSessionToken"
    private let trialDays = 14
    private let periodicRevalidationSeconds: TimeInterval = 12 * 60 * 60
    private let translationRevalidationSeconds: TimeInterval = 24 * 60 * 60
    private let offlineGraceSeconds: TimeInterval = 30 * 24 * 60 * 60

    private let client: MagicCodeAuthClientProtocol
    private let store: AccountStoring
    private let userDefaults: UserDefaults
    private let now: () -> Date
    private let openURLHandler: (URL) -> Void
    private let startBackgroundTasks: Bool

    private var revalidationTask: Task<Void, Never>?

    init(
        client: MagicCodeAuthClientProtocol = MagicCodeAuthClient(),
        store: AccountStoring = AccountStore(),
        userDefaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        openURLHandler: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
        startBackgroundTasks: Bool = true
    ) {
        self.client = client
        self.store = store
        self.userDefaults = userDefaults
        self.now = now
        self.openURLHandler = openURLHandler
        self.startBackgroundTasks = startBackgroundTasks

        clearLegacyLemonStoreIfPresent()
        clearLegacySessionKeys()
        loadState()
        if startBackgroundTasks {
            startPeriodicRevalidation()
        }

        if startBackgroundTasks, store.read() != nil {
            Task { [weak self] in
                await self?.refreshSubscriptionStatus(forceNetwork: false)
            }
        }
    }

    func loadState() {
        lastError = nil

        guard let record = store.read(), !record.sessionToken.isEmpty else {
            state = localTrialOrExpiredState()
            return
        }

        if let lastValidatedAt = record.lastValidatedAt,
           record.subscriptionStatus?.lowercased() == "active",
           now().timeIntervalSince(lastValidatedAt) <= offlineGraceSeconds {
            state = .active(planName: record.planName, validatedAt: lastValidatedAt, isOfflineGrace: true)
            return
        }

        // Signed in but no active subscription cached → fall back to trial calc.
        state = localTrialOrExpiredState()
    }

    /// Step 1 of sign-in: request a magic code be emailed.
    func requestMagicCode(email: String) async -> Bool {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty, normalized.contains("@") else {
            lastError = "Enter a valid email"
            return false
        }

        isLoading = true
        defer { isLoading = false }

        do {
            try await client.requestMagicCode(email: normalized)
            pendingMagicCodeEmail = normalized
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Step 2 of sign-in: verify the magic code and store the session token.
    func verifyMagicCode(_ code: String) async -> Bool {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let email = pendingMagicCodeEmail, !normalized.isEmpty else {
            lastError = "Enter the 6-digit code"
            return false
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let token = try await client.verifyMagicCode(email: email, code: normalized)
            let record = StoredAccountRecord(
                email: email,
                sessionToken: token,
                subscriptionStatus: nil,
                planName: nil,
                lastValidatedAt: nil
            )
            store.save(record)
            pendingMagicCodeEmail = nil
            lastError = nil

            // Check subscription status immediately after sign-in.
            await refreshSubscriptionStatus(forceNetwork: true)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Cancel the current pending sign-in (user clicked "back" or "cancel").
    func cancelPendingSignIn() {
        pendingMagicCodeEmail = nil
        lastError = nil
    }

    /// Refresh subscription status. Used both manually and periodically.
    func refreshSubscriptionStatus(forceNetwork: Bool = false) async {
        guard !isLoading else { return }
        guard var record = store.read(), !record.sessionToken.isEmpty else {
            state = localTrialOrExpiredState()
            return
        }

        let shouldSkipNetwork = !forceNetwork &&
            record.subscriptionStatus?.lowercased() == "active" &&
            isWithinRevalidationWindow(record.lastValidatedAt)

        if shouldSkipNetwork {
            if let validatedAt = record.lastValidatedAt {
                state = .active(
                    planName: record.planName,
                    validatedAt: validatedAt,
                    isOfflineGrace: false
                )
            }
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let status = try await client.refreshSubscriptionStatus(token: record.sessionToken)

            record.subscriptionStatus = status.status.rawValue
            record.planName = status.planName ?? record.planName
            record.lastValidatedAt = now()
            store.save(record)

            switch status.status {
            case .active:
                state = .active(
                    planName: record.planName,
                    validatedAt: record.lastValidatedAt ?? now(),
                    isOfflineGrace: false
                )
                lastError = nil
            case .trial:
                state = localTrialOrExpiredState()
            case .pastDue:
                state = .invalid(reason: "Payment past due. Please update your card.")
            case .canceled, .expired:
                state = localTrialOrExpiredState()
            case .unknown:
                state = localTrialOrExpiredState()
            }
        } catch let error as AuthError {
            // 401 invalid session → clear stored token and fall back to trial.
            if case .server(let status, _) = error, status == 401 {
                store.delete()
                state = localTrialOrExpiredState()
                lastError = "Session expired. Please sign in again."
                return
            }

            // Network error → use cached status if within offline grace.
            applyOfflineFallback(record: record, errorMessage: error.localizedDescription)
        } catch {
            applyOfflineFallback(record: record, errorMessage: error.localizedDescription)
        }
    }

    /// Open Stripe Checkout in the browser. Requires being signed in.
    func openUpgrade() async {
        guard let token = storedSessionToken else {
            lastError = "Sign in first to subscribe"
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let url = try await client.createCheckoutSession(token: token)
            openURLHandler(url)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Open Stripe Customer Portal. Requires being signed in with a subscription.
    func openManageSubscription() async {
        guard let token = storedSessionToken else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let url = try await client.createPortalSession(token: token)
            openURLHandler(url)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Sign out: delete session and revert to trial/expired.
    func signOut() {
        store.delete()
        pendingMagicCodeEmail = nil
        lastError = nil
        loadState()
    }

    func applyDebugState(_ debugState: LicenseState) {
        revalidationTask?.cancel()
        isLoading = false
        lastError = nil
        state = debugState
    }

    // MARK: - Private

    private func startPeriodicRevalidation() {
        revalidationTask?.cancel()
        revalidationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                try? await Task.sleep(nanoseconds: UInt64(self.periodicRevalidationSeconds * 1_000_000_000))
                if Task.isCancelled { break }
                await self.refreshSubscriptionStatus(forceNetwork: true)
            }
        }
    }

    private func clearLegacySessionKeys() {
        userDefaults.removeObject(forKey: legacyAuthEmailKey)
        userDefaults.removeObject(forKey: legacySessionTokenKey)
    }

    /// Old Lemon Squeezy users will have a license_state.enc file. Clear it on first launch
    /// of v2.0.0 so they get a clean re-registration experience.
    private func clearLegacyLemonStoreIfPresent() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let base = appSupport else { return }
        let lemonURL = base
            .appendingPathComponent(Constants.appName, isDirectory: true)
            .appendingPathComponent(legacyLemonStoreFile, isDirectory: false)
        try? FileManager.default.removeItem(at: lemonURL)
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

    private func applyOfflineFallback(record: StoredAccountRecord, errorMessage: String) {
        lastError = errorMessage

        if let lastValidatedAt = record.lastValidatedAt,
           record.subscriptionStatus?.lowercased() == "active",
           now().timeIntervalSince(lastValidatedAt) <= offlineGraceSeconds {
            state = .active(
                planName: record.planName,
                validatedAt: lastValidatedAt,
                isOfflineGrace: true
            )
            return
        }

        state = localTrialOrExpiredState()
    }
}
