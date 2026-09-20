import ControlVCore
import StoreKit
import SwiftUI

/// Full-screen subscription screen. Price and trial come from StoreKit.
/// Dismissable while the trial is still running; mandatory once it ends.
/// Shown as an overlay by RootTabView; `onClose` hides it.
struct PaywallView: View {
    var onClose: () -> Void = {}
    @Environment(StoreKitSubscriptionManager.self) private var subscriptions
    @Environment(LicenseService.self) private var license
    @State private var isWorking = false
    @State private var hasLoaded = false
    @State private var trialDays: Int?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(spacing: 22) {
                    BrandMark(size: 72).padding(.top, 36)
                    VStack(spacing: 8) {
                        Text("Write in any language,\nlike a native.")
                            .font(.system(size: 32, weight: .bold)).multilineTextAlignment(.center)
                        Text("Select text in any app, tap Translate, and it's replaced with a natural translation.")
                            .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 12)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        benefit("text.cursor", "Replace text in any app", "Select → Translate → Replace in Messages, WhatsApp, Mail, Notes.")
                        benefit("person.wave.2", "Sounds like you", "Keeps your tone, slang and formatting. Five tones plus your own.")
                        benefit("laptopcomputer.and.iphone", "Mac and iPhone", "One subscription, all your devices.")
                        benefit("lock.shield", "Private by design", "Only the text you choose is sent. Never stored on our servers, never logged.")
                    }
                    .padding(18)
                    .glassCard(24)

                    pricing
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
        }
        .overlay(alignment: .topTrailing) {
            if canDismiss {
                Button { onClose() } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .glassPill()
                }
                .buttonStyle(.plain)
                .padding(.trailing, 20)
                .padding(.top, 8)
                .accessibilityLabel("Not now")
            }
        }
        .task { await load() }
    }

    // MARK: - Pricing

    @ViewBuilder
    private var pricing: some View {
        VStack(spacing: 10) {
            if let product = subscriptions.product {
                Button { Task { await purchase(product) } } label: {
                    VStack(spacing: 2) {
                        Text(ctaTitle).font(.headline)
                        Text(ctaDetail(for: product)).font(.caption).opacity(0.85)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isWorking)
            } else if hasLoaded {
                VStack(spacing: 10) {
                    Text(subscriptions.loadError ?? "Pricing couldn't be loaded. Check your connection and try again.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button { Task { await load() } } label: { Label("Try again", systemImage: "arrow.clockwise") }
                        .buttonStyle(GlassButtonStyle())
                }
                .padding(.vertical, 4)
            } else {
                ProgressView().padding(.vertical, 16)
            }
            Button("Restore purchase") { Task { await restore() } }
                .font(.subheadline).foregroundStyle(.secondary).disabled(isWorking)
            HStack(spacing: 16) {
                Link("Privacy Policy", destination: URL(string: "https://control-v.info/privacy")!)
                Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
            }
            .font(.caption2).foregroundStyle(.tertiary)
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center)
            }
        }
    }

    private var canDismiss: Bool {
        switch license.state {
        case .trial, .active: return true
        case .checking, .expired, .invalid: return false
        }
    }

    private var ctaTitle: String {
        if let trialDays { return "Start \(trialDays)-day free trial" }
        return "Subscribe to Control-V Pro"
    }

    private func ctaDetail(for product: Product) -> String {
        trialDays == nil
            ? "\(product.displayPrice) / month · cancel anytime"
            : "Then \(product.displayPrice) / month · cancel anytime"
    }

    // MARK: - Actions

    private func load() async {
        hasLoaded = false
        await subscriptions.loadProducts()
        trialDays = await Self.freeTrialDays(for: subscriptions.product)
        hasLoaded = true
    }

    /// Days of free trial this Apple ID is actually eligible for (nil = none,
    /// so the CTA says "Subscribe" instead of promising a trial it won't get).
    private static func freeTrialDays(for product: Product?) async -> Int? {
        guard let subscription = product?.subscription,
              let offer = subscription.introductoryOffer,
              offer.paymentMode == .freeTrial,
              await subscription.isEligibleForIntroOffer else { return nil }
        switch offer.period.unit {
        case .day: return offer.period.value
        case .week: return offer.period.value * 7
        case .month: return offer.period.value * 30
        case .year: return offer.period.value * 365
        @unknown default: return nil
        }
    }

    private func purchase(_ product: Product) async {
        errorMessage = nil; isWorking = true; defer { isWorking = false }
        do {
            try await subscriptions.purchase(product)
            if subscriptions.isSubscribed { onClose() }
        } catch { errorMessage = error.localizedDescription }
    }

    private func restore() async {
        errorMessage = nil; isWorking = true; defer { isWorking = false }
        do {
            try await subscriptions.restore()
            if subscriptions.isSubscribed { onClose() } else { errorMessage = "No active subscription found for this Apple Account." }
        } catch { errorMessage = error.localizedDescription }
    }

    private func benefit(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.body.weight(.semibold)).foregroundStyle(.white)
                .frame(width: 34, height: 34).background(Brand.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
