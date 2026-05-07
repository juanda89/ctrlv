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

    deinit {
        transactionObserver?.cancel()
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
            await forwardToBackend(transaction: transaction)
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
            await forwardToBackend(transaction: transaction)
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

    /// Forward the StoreKit transaction to the backend so it can update
    /// `account_subscriptions` with provider="appstore". This call is best-effort:
    /// if the user is not signed in (no email account), we still grant local
    /// subscription via Transaction.currentEntitlements.
    private func forwardToBackend(transaction: Transaction) async {
        guard let token = licenseService.storedSessionToken,
              let baseURL = Constants.authAPIBaseURL else {
            // No backend account linked — that's fine. StoreKit is the source
            // of truth on this device. User can sign in later to sync.
            return
        }

        let url = baseURL.appendingPathComponent("validate-appstore-receipt")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let payload: [String: Any] = [
            "originalTransactionID": String(transaction.originalID),
            "transactionID": String(transaction.id),
            "productID": transaction.productID,
            "purchaseDate": ISO8601DateFormatter().string(from: transaction.purchaseDate),
            "expiresAt": transaction.expirationDate.map { ISO8601DateFormatter().string(from: $0) } as Any,
            "appAccountToken": transaction.appAccountToken?.uuidString as Any
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        _ = try? await URLSession.shared.data(for: request)
    }
}
