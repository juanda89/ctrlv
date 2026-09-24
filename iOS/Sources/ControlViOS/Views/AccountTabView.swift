import ControlVCore
import SwiftUI

struct AccountTabView: View {
    @Environment(LicenseService.self) private var license
    @Environment(StoreKitSubscriptionManager.self) private var subscriptions
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSignIn = DebugLaunch.showSignIn
    @State private var showSetup = false
    @State private var showFeedback = DebugLaunch.showFeedback
    @State private var isSetUp = SetupState.anyReady
    @State private var confirmingDeletion = false
    @State private var deletionOutcome: DeletionOutcome?

    private enum DeletionOutcome: Identifiable {
        case deleted, failed(String)
        var id: String {
            switch self {
            case .deleted: "deleted"
            case .failed(let message): message
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // Nothing else matters until the user can translate outside
                    // the app, so that card comes first and the rest is inert.
                    if !isSetUp { setupCard }

                    VStack(spacing: 14) {
                        statusHero
                        accountCard
                        linksCard
                        Text("Control-V \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 6)
                    }
                    .opacity(isSetUp ? 1 : 0.4)
                    .disabled(!isSetUp)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 32)
            }
            .background(AuroraBackground())
            .navigationTitle("Account")
            .task(id: scenePhase) { isSetUp = SetupState.anyReady }
            .onReceive(NotificationCenter.default.publisher(for: .controlVSetupChanged)) { _ in isSetUp = SetupState.anyReady }
            .sheet(isPresented: $showSignIn) { SignInScreen().presentationDetents([.large]).presentationDragIndicator(.visible) }
            .sheet(isPresented: $showSetup, onDismiss: { isSetUp = SetupState.anyReady }) {
                KeyboardSetupView { showSetup = false }
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $showFeedback) { FeedbackSheet(initialRating: nil).presentationDetents([.large]).presentationDragIndicator(.visible) }
            .alert("Delete your account?", isPresented: $confirmingDeletion) {
                Button("Delete account", role: .destructive) { Task { await deleteAccount() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes the Control-V account \(signedInEmail ?? "") and signs you out on all your devices. A subscription paid on control-v.info is cancelled now. A subscription bought in the App Store is billed by Apple until you cancel it in Settings › your name › Subscriptions.")
            }
            .alert(item: $deletionOutcome) { outcome in
                switch outcome {
                case .deleted where subscriptions.isSubscribed:
                    return Alert(
                        title: Text("Account deleted"),
                        message: Text("Your Control-V account and its data were deleted. Your App Store subscription is still active: cancel it there if you no longer want it."),
                        primaryButton: .default(Text("Manage subscription")) { Task { await subscriptions.openManageSubscription() } },
                        secondaryButton: .cancel(Text("OK"))
                    )
                case .deleted:
                    return Alert(
                        title: Text("Account deleted"),
                        message: Text("Your Control-V account and its data were deleted."),
                        dismissButton: .default(Text("OK"))
                    )
                case .failed(let message):
                    return Alert(title: Text("Account not deleted"), message: Text(message), dismissButton: .default(Text("OK")))
                }
            }
        }
    }

    // MARK: - Cards

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Finish setup", systemImage: "exclamationmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("Control-V translates text inside other apps. Turn on the Translate menu or the Control-V keyboard once, and you're done.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button { showSetup = true } label: { Label("Set it up", systemImage: "arrow.right") }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(22)
    }

    private var statusHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                BrandMark(size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle).font(.title3.weight(.bold))
                    Text(statusDetail).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                if case .active = license.state {
                    Button { Task { await subscriptions.openManageSubscription() } } label: { Label("Manage", systemImage: "creditcard") }
                        .buttonStyle(GlassButtonStyle())
                } else {
                    Button { NotificationCenter.default.post(name: .controlVShowPaywall, object: nil) } label: { Label("Go Pro", systemImage: "sparkles") }
                        .buttonStyle(PrimaryButtonStyle())
                }
                Button { Task { try? await subscriptions.restore() } } label: { Text("Restore") }
                    .buttonStyle(GlassButtonStyle())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(22)
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Sync with your Mac", systemImage: "laptopcomputer.and.iphone").font(.headline)
            if let email = signedInEmail {
                HStack(spacing: 10) {
                    Text(email)
                        .font(.subheadline).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    Button("Sign out", role: .destructive) { license.signOut(); AppGroupBridge.syncSessionToken(from: license) }
                        .buttonStyle(GlassButtonStyle())
                        .fixedSize()
                }
                Button(role: .destructive) { confirmingDeletion = true } label: {
                    if license.isLoading { ProgressView() } else { Label("Delete account", systemImage: "trash") }
                }
                .font(.subheadline)
                .foregroundStyle(.red)
                .disabled(license.isLoading)
                .accessibilityIdentifier("account.delete")
            } else {
                Text("One subscription covers all your devices. Sign in with the email you use on the Mac app.")
                    .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button { showSignIn = true } label: { Label("Sign in with email", systemImage: "envelope") }
                    .buttonStyle(GlassButtonStyle())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(22)
    }

    private var linksCard: some View {
        VStack(spacing: 0) {
            Button { showFeedback = true } label: {
                row(title: "Leave feedback", symbol: "star.bubble", trailing: "chevron.right")
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 48)
            // Always reachable: this is where the user checks or fixes how
            // Control-V translates in other apps, set up or not.
            Button { showSetup = true } label: {
                row(title: "Translating in other apps", symbol: "slider.horizontal.3", trailing: "chevron.right")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("account.setupRow")
            Divider().padding(.leading, 48)
            linkRow("Website", "globe", "https://control-v.info")
            Divider().padding(.leading, 48)
            linkRow("Privacy Policy", "hand.raised", "https://control-v.info/privacy")
            Divider().padding(.leading, 48)
            linkRow("Contact support", "envelope", "mailto:info@control-v.info")
        }
        .frame(maxWidth: .infinity)
        .glassCard(22)
    }

    private func row(title: String, symbol: String, trailing: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 22).foregroundStyle(Brand.blue)
            Text(title).foregroundStyle(.primary)
            Spacer(minLength: 0)
            Image(systemName: trailing).font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    private func linkRow(_ title: String, _ symbol: String, _ url: String) -> some View {
        Link(destination: URL(string: url)!) {
            row(title: title, symbol: symbol, trailing: "arrow.up.right")
        }
    }

    private func deleteAccount() async {
        if await license.deleteAccount() {
            AppGroupBridge.syncSessionToken(from: license)
            // An App Store subscription outlives the account: re-link it to
            // this install so translation stays on the paid plan.
            await subscriptions.refreshOnLaunch()
            deletionOutcome = .deleted
        } else {
            deletionOutcome = .failed(license.lastError ?? "Try again in a minute.")
        }
    }

    private var signedInEmail: String? {
        if DebugLaunch.fakeSignedIn { return "you@example.com" }
        return license.isSignedIn ? license.storedEmail : nil
    }

    // MARK: - Status

    private var statusTitle: String {
        switch license.state {
        case .checking: return "Checking…"
        case .trial: return "Free trial"
        case .active: return "Control-V Pro"
        case .expired: return "Trial ended"
        case .invalid: return "Attention needed"
        }
    }

    private var statusDetail: String {
        switch license.state {
        case .checking: return ""
        case .trial(let days):
            let base = "\(days) day\(days == 1 ? "" : "s") left"
            guard let price = subscriptions.product?.displayPrice else { return base }
            return "\(base) · then \(price)/month"
        case .active(_, _, let offline):
            if offline { return "Active · offline mode" }
            return license.isSignedIn ? "Active on all your devices" : "Active · App Store subscription"
        case .expired: return "Subscribe to keep translating"
        case .invalid(let reason): return reason
        }
    }
}

extension Notification.Name {
    static let controlVShowPaywall = Notification.Name("controlv.showPaywall")
}
