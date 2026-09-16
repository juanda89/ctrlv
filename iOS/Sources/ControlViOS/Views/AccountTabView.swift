import ControlVCore
import SwiftUI

struct AccountTabView: View {
    @Environment(LicenseService.self) private var license
    @Environment(StoreKitSubscriptionManager.self) private var subscriptions
    @State private var showSignIn = DebugLaunch.showSignIn
    @State private var showSetup = false
    @State private var showFeedback = DebugLaunch.showFeedback
    @State private var feedbackRating: Int?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    statusHero
                    keyboardCard
                    syncCard
                    feedbackCard
                    linksCard
                    Text("Control-V \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 32)
            }
            .background(AuroraBackground())
            .navigationTitle("Account")
            .sheet(isPresented: $showSignIn) { SignInScreen().presentationDetents([.large]).presentationDragIndicator(.visible) }
            .sheet(isPresented: $showSetup) { KeyboardSetupView { showSetup = false }.presentationDetents([.large]).presentationDragIndicator(.visible) }
            .sheet(isPresented: $showFeedback) { FeedbackSheet(initialRating: feedbackRating).presentationDetents([.large]).presentationDragIndicator(.visible) }
        }
    }

    // MARK: - Cards

    private var statusHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                BrandMark(size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle).font(.title3.weight(.bold))
                    Text(statusDetail).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
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
        .glassCard(22)
    }

    private var keyboardCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Translate in any app", systemImage: "keyboard").font(.headline)
                Spacer()
            }
            Text("Make Control-V your default translation app: select text in Messages, WhatsApp or Mail, tap Translate, tap Replace. The Control-V keyboard also translates what you just typed.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button { showSetup = true } label: { Label("Set it up", systemImage: "arrow.right") }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(16)
        .glassCard(22)
    }

    private var syncCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Sync with your Mac", systemImage: "laptopcomputer.and.iphone").font(.headline)
            if license.isSignedIn, let email = license.storedEmail {
                Text("Signed in as \(email)").font(.subheadline).foregroundStyle(.secondary)
                Button("Sign out", role: .destructive) { license.signOut(); AppGroupBridge.syncSessionToken(from: license) }
                    .buttonStyle(GlassButtonStyle())
            } else {
                Text("One subscription covers all your devices. Sign in with the email you use on the Mac app.")
                    .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button { showSignIn = true } label: { Label("Sign in with email", systemImage: "envelope") }
                    .buttonStyle(GlassButtonStyle())
            }
        }
        .padding(16)
        .glassCard(22)
    }

    private var feedbackCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How's Control-V working for you?").font(.headline)
            Text("Rate it, request a feature, or tell us what broke.").font(.subheadline).foregroundStyle(.secondary)
            HStack {
                HStack(spacing: 6) {
                    ForEach(1...5, id: \.self) { star in
                        Button { feedbackRating = star; showFeedback = true } label: {
                            Image(systemName: "star").font(.title3).foregroundStyle(Color(red: 0.98, green: 0.74, blue: 0.20))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer()
                Button { feedbackRating = nil; showFeedback = true } label: { Text("Leave feedback ›").font(.subheadline.weight(.semibold)).foregroundStyle(Brand.blue) }
                    .buttonStyle(.plain)
            }
        }
        .padding(16)
        .glassCard(22)
    }

    private var linksCard: some View {
        VStack(spacing: 0) {
            linkRow("Website", "globe", "https://control-v.info")
            Divider().padding(.leading, 44)
            linkRow("Privacy Policy", "hand.raised", "https://control-v.info/privacy")
            Divider().padding(.leading, 44)
            linkRow("Contact support", "envelope", "mailto:info@control-v.info")
        }
        .glassCard(22)
    }

    private func linkRow(_ title: String, _ symbol: String, _ url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 12) {
                Image(systemName: symbol).frame(width: 20).foregroundStyle(Brand.blue)
                Text(title).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
    }

    // MARK: - Status

    private var statusTitle: String {
        switch license.state {
        case .checking: return "Checking…"
        case .trial: return "Free trial"
        case .active(let plan, _, _): return (plan?.isEmpty == false ? plan! : "Pro")
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
        case .active(_, _, let offline): return offline ? "Active · offline mode" : "Active on all your devices"
        case .expired: return "Subscribe to keep translating"
        case .invalid(let reason): return reason
        }
    }
}

extension Notification.Name {
    static let controlVShowPaywall = Notification.Name("controlv.showPaywall")
}
