import ControlVCore
import StoreKit
import SwiftUI

/// Full-screen subscription paywall using StoreKit's native trial UX:
/// "14-day free trial, then $8.99/month — cancel anytime in Settings".
struct PaywallView: View {
    @Environment(StoreKitSubscriptionManager.self) private var subscriptions
    @Environment(\.dismiss) private var dismiss
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)

                Text("Translate anywhere on iOS")
                    .font(.title.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text("Select text in any app, share to Control-V, and get a natural-sounding translation in seconds.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "infinity", text: "Unlimited translations")
                FeatureRow(icon: "globe", text: "12 languages")
                FeatureRow(icon: "wand.and.stars", text: "Multiple tone presets")
                FeatureRow(icon: "lock.shield", text: "Your text stays private")
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                if let product = subscriptions.product {
                    Button {
                        Task { await purchase(product) }
                    } label: {
                        VStack(spacing: 4) {
                            Text("Start 14-day free trial")
                                .font(.headline)
                            Text("Then \(product.displayPrice) / month — cancel anytime")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.tint)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(isWorking)
                    .padding(.horizontal, 24)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }

                Button("Restore Purchase") {
                    Task { await restore() }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .disabled(isWorking)

                // Required by App Store Guideline 3.1.2 for auto-renewable subscriptions
                HStack(spacing: 16) {
                    Link("Privacy Policy", destination: URL(string: "https://control-v.info/privacy")!)
                    Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
            .padding(.bottom, 24)
        }
        .padding(.top, 60)
        .task {
            await subscriptions.loadProducts()
        }
    }

    private func purchase(_ product: Product) async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await subscriptions.purchase(product)
            // On success, RootTabView re-evaluates shouldShowPaywall
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restore() async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await subscriptions.restore()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.tint)
                .frame(width: 22)
            Text(text)
                .font(.body)
        }
    }
}
