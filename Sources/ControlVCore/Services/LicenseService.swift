import Foundation

@MainActor
@Observable
public final class LicenseService {
    public private(set) var state: LicenseState = .checking {
        didSet {
            if state != oldValue {
                onStateChange?(state)
            }
        }
    }
    public private(set) var isLoading = false
    public private(set) var lastError: String?

    /// Authentication progress flag for the sign-in flow.
    public private(set) var pendingMagicCodeEmail: String?

    /// Last email a magic code was requested for. Persisted and kept across
    /// sign-out so the sign-in form can prefill it — the user doesn't have to
    /// remember which email their subscription is under.
    public private(set) var lastSignInEmail: String?

    public var storedSessionToken: String? {
        _ = accountRevision
        return store.read()?.sessionToken
    }

    public var storedEmail: String? {
        _ = accountRevision
        return store.read()?.email
    }

    /// The account store is a file, invisible to Observation. Every write
    /// bumps this, and the accessors above read it, so views that show the
    /// signed-in email re-render on sign-in and sign-out. Without it a sign-in
    /// that leaves `state` unchanged (trial before, trial after) redraws
    /// nothing: @Observable skips notifications for equal values.
    private var accountRevision = 0

    private func saveAccount(_ record: StoredAccountRecord) {
        store.save(record)
        accountRevision += 1
    }

    private func deleteAccountRecord() {
        store.delete()
        accountRevision += 1
    }

    /// iOS: StoreKit reports an active App Store subscription on this device.
    /// It counts as the paid plan whenever the server has none for the
    /// session, so a purchase works without an account (App Review 5.1.1);
    /// the server grants the same through the install link. Never set on macOS.
    public private(set) var hasStoreEntitlement = false

    public var isSignedIn: Bool {
        _ = accountRevision
        guard let record = store.read() else { return false }
        return !record.sessionToken.isEmpty
    }

    private let installDateKey = "installDate"
    private let lastSignInEmailKey = "lastSignInEmail"
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

    /// Optional state-change observer (used by Mac for telemetry; iOS can use too).
    private let onStateChange: ((LicenseState) -> Void)?

    private var revalidationTask: Task<Void, Never>?

    public init(
        client: MagicCodeAuthClientProtocol = MagicCodeAuthClient(),
        store: AccountStoring = AccountStore(),
        userDefaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        openURLHandler: @escaping (URL) -> Void,
        startBackgroundTasks: Bool = true,
        onStateChange: ((LicenseState) -> Void)? = nil
    ) {
        self.client = client
        self.store = store
        self.userDefaults = userDefaults
        self.now = now
        self.openURLHandler = openURLHandler
        self.startBackgroundTasks = startBackgroundTasks
        self.onStateChange = onStateChange
        self.lastSignInEmail = userDefaults.string(forKey: lastSignInEmailKey)

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

    public func loadState() {
        lastError = nil
        if let debugStateOverride {
            state = debugStateOverride
            return
        }

        guard let record = store.read(), !record.sessionToken.isEmpty else {
            state = unpaidState()
            return
        }

        if let lastValidatedAt = record.lastValidatedAt,
           record.subscriptionStatus?.lowercased() == "active",
           now().timeIntervalSince(lastValidatedAt) <= offlineGraceSeconds {
            state = .active(planName: record.planName, validatedAt: lastValidatedAt, isOfflineGrace: true)
            return
        }

        // Signed in but no active subscription cached → fall back to trial calc.
        state = unpaidState()
    }

    /// Step 1 of sign-in: request a magic code be emailed.
    public func requestMagicCode(email: String) async -> Bool {
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
            lastSignInEmail = normalized
            userDefaults.set(normalized, forKey: lastSignInEmailKey)
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Step 2 of sign-in: verify the magic code and store the session token.
    public func verifyMagicCode(_ code: String) async -> Bool {
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
            saveAccount(record)
            pendingMagicCodeEmail = nil
            lastError = nil

            // Release the loading lock so refreshSubscriptionStatus can proceed.
            // (refreshSubscriptionStatus has its own re-entry guard.)
            isLoading = false

            // Check subscription status immediately after sign-in.
            await refreshSubscriptionStatus(forceNetwork: true)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Cancel the current pending sign-in (user clicked "back" or "cancel").
    public func cancelPendingSignIn() {
        pendingMagicCodeEmail = nil
        lastError = nil
    }

    /// Refresh subscription status. Used both manually and periodically.
    public func refreshSubscriptionStatus(forceNetwork: Bool = false) async {
        guard !isLoading else { return }
        if let debugStateOverride {
            state = debugStateOverride
            return
        }
        guard var record = store.read(), !record.sessionToken.isEmpty else {
            state = unpaidState()
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
            saveAccount(record)

            switch status.status {
            case .active:
                state = .active(
                    planName: record.planName,
                    validatedAt: record.lastValidatedAt ?? now(),
                    isOfflineGrace: false
                )
                lastError = nil
            case .trial:
                state = unpaidState()
            case .pastDue:
                state = .invalid(reason: "Payment past due. Please update your card.")
            case .canceled, .expired:
                state = unpaidState()
            case .unknown:
                state = unpaidState()
            }
        } catch let error as AuthError {
            // 401 invalid session → clear stored token and fall back to trial.
            if case .server(let status, _) = error, status == 401 {
                deleteAccountRecord()
                state = unpaidState()
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
    /// Always re-validates subscription status first — protects against stale
    /// cache, network errors during last refresh, or multi-device payments.
    public func openUpgrade() async {
        guard let token = storedSessionToken else {
            lastError = "Sign in first to subscribe"
            return
        }

        // Force-refresh status before creating a checkout session. If user
        // already has an active subscription (e.g. paid on another device,
        // or just returned from Stripe and cache was stale), state will
        // update and the SwiftUI view will re-render — no checkout opened.
        await refreshSubscriptionStatus(forceNetwork: true)

        if case .active = state {
            // Already subscribed; UI will react to state change.
            lastError = nil
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
    public func openManageSubscription() async {
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

    /// Permanently deletes the signed-in account on the server, then signs
    /// out locally. Returns false (with `lastError` set) when the server did
    /// not confirm; the session is kept so the user can retry.
    public func deleteAccount() async -> Bool {
        guard let token = storedSessionToken else {
            lastError = "Sign in to delete your account"
            return false
        }

        isLoading = true
        defer { isLoading = false }

        do {
            try await client.deleteAccount(token: token)
            signOut()
            return true
        } catch let error as AuthError {
            if case .server(let status, _) = error, status == 401 {
                lastError = "Your session expired. Sign in again, then delete the account."
            } else {
                lastError = error.localizedDescription
            }
            return false
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    public func setStoreEntitlement(_ active: Bool) {
        guard active != hasStoreEntitlement else { return }
        hasStoreEntitlement = active
        loadState()
    }

    /// Sign out: delete session and revert to trial/expired.
    public func signOut() {
        deleteAccountRecord()
        pendingMagicCodeEmail = nil
        lastError = nil
        loadState()
    }

    /// Debug/preview override (menu snapshots, iOS `-ui.licenseState`). While
    /// set, `loadState` and `refreshSubscriptionStatus` keep it instead of
    /// recomputing: launch-time refreshes otherwise race with the override
    /// and silently replace it.
    private var debugStateOverride: LicenseState?

    public func applyDebugState(_ debugState: LicenseState) {
        revalidationTask?.cancel()
        isLoading = false
        lastError = nil
        debugStateOverride = debugState
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

    /// State when the server confirmed no paid plan (or cannot be reached).
    private func unpaidState() -> LicenseState {
        if hasStoreEntitlement {
            return .active(planName: nil, validatedAt: now(), isOfflineGrace: false)
        }
        return localTrialOrExpiredState()
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

        state = unpaidState()
    }
}
