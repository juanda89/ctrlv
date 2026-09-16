import ControlVCore
import Foundation
import Observation
import StoreKit
import UIKit

/// StoreKit 2 subscription manager for Control-V Pro.
/// - Product: `info.controlv.pro.monthly` configured in App Store Connect
///   with a 14-day Introductory Offer (free trial), then $8.99/month recurring.
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

    init(licenseService: LicenseService) {
        self.licenseService = licenseService
        observeTransactions()
    }

    func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.productID])
            self.product = products.first
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
        var hasActive = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if transaction.productID == Self.productID,
               transaction.revocationDate == nil,
               (transaction.expirationDate ?? .distantFuture) > Date() {
                hasActive = true
            }
        }
        self.isSubscribed = hasActive

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
    /// verifies Apple's signature chain server-side before updating
    /// `account_subscriptions` with provider="appstore". Best-effort: without a
    /// signed-in account there is nothing to link yet; StoreKit remains the
    /// source of truth on this device and the user can sign in later to sync.
    private func forwardToBackend(signedTransaction: String) async {
        guard let token = licenseService.storedSessionToken,
              let baseURL = Constants.authAPIBaseURL else {
            return
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("validate-appstore-receipt"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["signedTransaction": signedTransaction])
        _ = try? await URLSession.shared.data(for: request)
    }
}
