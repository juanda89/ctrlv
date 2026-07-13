import ControlVCore
import SwiftUI

struct AccountTabView: View {
    @Environment(LicenseService.self) private var license
    @Environment(StoreKitSubscriptionManager.self) private var subscriptions

    var body: some View {
        NavigationStack {
            Form {
                Section("Subscription") {
                    statusRow

                    if subscriptions.isSubscribed {
                        Button {
                            Task { await subscriptions.openManageSubscription() }
                        } label: {
                            Label("Manage Subscription", systemImage: "person.crop.circle.badge.checkmark")
                        }
                    }

                    Button {
                        Task { try? await subscriptions.restore() }
                    } label: {
                        Label("Restore Purchase", systemImage: "arrow.clockwise.circle")
                    }
                }

                Section("Sync across devices") {
                    if license.isSignedIn, let email = license.storedEmail {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Signed in as")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(email)
                                .font(.body)
                        }

                        Button("Sign Out", role: .destructive) {
                            license.signOut()
                            AppGroupBridge.syncSessionToken(from: license)
                        }
                    } else {
                        NavigationLink {
                            SignInScreen()
                        } label: {
                            Label("Sign in with email", systemImage: "envelope")
                        }
                        Text("Optional. Sign in to sync your subscription with the macOS app.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Link(destination: URL(string: "https://control-v.info")!) {
                        Label("Website", systemImage: "globe")
                    }
                    Link(destination: URL(string: "https://control-v.info/privacy")!) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                    Link(destination: URL(string: "mailto:info@control-v.info")!) {
                        Label("Contact Support", systemImage: "envelope")
                    }
                }
            }
            .navigationTitle("Account")
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch license.state {
        case .checking:
            HStack { ProgressView(); Text("Checking…") }
        case .trial(let days):
            HStack {
                Image(systemName: "clock")
                Text("\(days) days remaining in trial")
            }
        case .active(let plan, _, _):
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text(plan?.isEmpty == false ? plan! : "Active subscription")
            }
        case .expired:
            HStack {
                Image(systemName: "xmark.seal.fill")
                    .foregroundStyle(.red)
                Text("Trial expired")
            }
        case .invalid(let reason):
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(reason)
                    .font(.callout)
            }
        }
    }
}
