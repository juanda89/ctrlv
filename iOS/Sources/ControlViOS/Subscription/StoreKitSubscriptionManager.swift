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

    func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.productID])
            self.product = products.first
            self.loadError = products.isEmpty ? "Pricing isn't available right now." : nil
            await refreshEntitlements()
        } catch {
            self.loadError = error.localizedDescription
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

    func openManageSubscription() async {
        guard let url = URL(string: "itms-apps://apps.apple.com/account/subscriptions") else {
            return
        }
        await UIApplication.shared.open(url)
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
    }
}
