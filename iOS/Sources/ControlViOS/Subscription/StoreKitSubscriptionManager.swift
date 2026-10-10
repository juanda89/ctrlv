import ControlVCore
import Foundation
import Observation
import StoreKit
import UIKit

/// StoreKit 2 subscription manager for Control-V Pro.
/// - Product: `info.controlv.pro.monthly` configured in App Store Connect
///   with a 14-day Introductory Offer (free trial), then USD 4.99/month.
/// - On purchase, the transaction is verified locally and forwarded to the
///   backend via `validate-appstore-receipt` so the same `account_subscriptions`
///   row is shared across Mac (Stripe) and iOS (App Store).
@MainActor
@Observable
final class StoreKitSubscriptionManager {
    static let productID = "info.controlv.pro.monthly"

    private let licenseService: LicenseService
    private(set) var product: Product?
    private(set) var isSubscribed = false
    private(set) var loadError: String?

    private var transactionObserver: Task<Void, Never>?
    /// Same App Group install ID the app and the extensions send to translate.
    private let installID = DeviceIdentityStore(
        userDefaults: UserDefaults(suiteName: SetupState.appGroup) ?? .standard
    ).currentInstallID()
    /// Last (transaction, session) pair the backend accepted; launch, paywall
    /// and restore all refresh entitlements, one POST per change is enough.
    private var lastForwarded: String?

    init(licenseService: LicenseService) {
        self.licenseService = licenseService
        observeTransactions()
    }

    /// Delays between attempts to fetch the product. The App Store's sandbox
    /// (TestFlight, App Review) intermittently answers with no products or an
    /// error; App Review rejected 1.0 (14) under 2.1(b) for "unavailable"
    /// products while the same product sold fine in TestFlight. A few quick
    /// retries ride out those blips before the paywall shows "Try again".
    static let productRetryDelays: [Duration] = [.seconds(1), .seconds(2), .seconds(3)]

    func loadProducts() async {
        if product == nil {
            product = await fetchProduct()
        }
        loadError = product == nil ? "Pricing isn't available right now. Check your connection and tap Try again." : nil
        await refreshEntitlements()
    }

    private func fetchProduct() async -> Product? {
        for delay in [Duration.zero] + Self.productRetryDelays {
            if delay > .zero { try? await Task.sleep(for: delay) }
            if let product = await fetchProductOnce(timeout: .seconds(5)) {
                return product
            }
        }
        return nil
    }

    /// One request, abandoned after `timeout`: a request that never answers
    /// would otherwise leave the paywall spinning with no way to retry.
    private func fetchProductOnce(timeout: Duration) async -> Product? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Product?, Never>) in
            let once = ResumeOnce(continuation)
            Task { @MainActor in
                once.resume(with: try? await Product.products(for: [Self.productID]).first)
            }
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                once.resume(with: nil)
            }
        }
    }

    func refreshOnLaunch() async {
        await loadProducts()
        await refreshEntitlements()
    }

    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await forwardToBackend(signedTransaction: verification.jwsRepresentation)
            await transaction.finish()
            await refreshEntitlements()
        case .userCancelled:
            return
        case .pending:
            // Ask-to-buy, parental approval, etc.
            return
        @unknown default:
            return
        }
    }

    func restore() async throws {
        try await AppStore.sync()
        await refreshEntitlements()
    }

    /// The subscription group in App Store Connect ("Control-V Pro").
    static let subscriptionGroupID = "22399702"

    /// StoreKit's own manage sheet: unlike the App Store's account page it
    /// also lists TestFlight and sandbox subscriptions, and it opens on ours.
    func openManageSubscription() async {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first {
            do {
                if #available(iOS 17.0, *) {
                    try await AppStore.showManageSubscriptions(in: scene, subscriptionGroupID: Self.subscriptionGroupID)
                } else {
                    try await AppStore.showManageSubscriptions(in: scene)
                }
                await refreshEntitlements()
                return
            } catch {
                // Fall through to the App Store's account page.
            }
        }
        if let url = URL(string: "itms-apps://apps.apple.com/account/subscriptions") {
            await UIApplication.shared.open(url)
        }
    }

    // MARK: - Internals

    private func observeTransactions() {
        transactionObserver = Task.detached { [weak self] in
            for await result in Transaction.updates {
                await self?.handleTransactionUpdate(result)
            }
        }
    }

    private func handleTransactionUpdate(_ result: VerificationResult<Transaction>) async {
        do {
            let transaction = try checkVerified(result)
            await forwardToBackend(signedTransaction: result.jwsRepresentation)
            await transaction.finish()
            await refreshEntitlements()
        } catch {
            // Verification failed — ignore the transaction.
        }
    }

    private func refreshEntitlements() async {
        var active: VerificationResult<Transaction>?
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if transaction.productID == Self.productID,
               transaction.revocationDate == nil,
               (transaction.expirationDate ?? .distantFuture) > Date() {
                active = result
            }
        }
        self.isSubscribed = active != nil
        licenseService.setStoreEntitlement(isSubscribed)

        // Keep the backend's copy current (renewals, a new session, a deleted
        // account): it links this install, and the account when signed in, so
        // the extensions translate on the paid plan too.
        if let active { await forwardToBackend(signedTransaction: active.jwsRepresentation) }

        // Sync down from backend so cached subscription state matches.
        await licenseService.refreshSubscriptionStatus(forceNetwork: true)
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value): return value
        case .unverified(_, let error): throw error
        }
    }

    /// Forward the SIGNED StoreKit transaction (JWS) to the backend, which
    /// verifies Apple's signature chain server-side, links the purchase to this
    /// install (no account needed: App Review forbids requiring one to buy)
    /// and, when signed in, to the account so the Mac shares the subscription.
    /// Best-effort: StoreKit stays the source of truth on this device.
    private func forwardToBackend(signedTransaction: String) async {
        guard let baseURL = Constants.authAPIBaseURL else { return }
        let token = licenseService.storedSessionToken
        let key = signedTransaction + "|" + (token ?? "")
        guard key != lastForwarded else { return }

        var request = URLRequest(url: baseURL.appendingPathComponent("validate-appstore-receipt"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "signedTransaction": signedTransaction,
            "installID": installID,
        ])
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return }
        lastForwarded = key
        // The server now grants this install the paid plan: a translation
        // sheet still showing "trial ended" can retry.
        AccessSignal.stamp()
    }
}

/// Resumes a continuation from whichever of two racing tasks finishes first.
@MainActor
private final class ResumeOnce {
    private var continuation: CheckedContinuation<Product?, Never>?

    init(_ continuation: CheckedContinuation<Product?, Never>) {
        self.continuation = continuation
    }

    func resume(with product: Product?) {
        continuation?.resume(returning: product)
        continuation = nil
    }
}
