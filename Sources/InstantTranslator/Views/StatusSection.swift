import SwiftUI

@MainActor
struct StatusSection: View {
    @Bindable var licenseService: LicenseService

    @State private var showSignIn = false
    @State private var showSubscribePrompt = false

    var body: some View {
        if showSignIn {
            SignInView(licenseService: licenseService) {
                showSignIn = false
            }
        } else if showSubscribePrompt {
            subscribePrompt
        } else {
            section
        }
    }

    @ViewBuilder
    private var section: some View {
        switch licenseService.state {
        case .active(let planName, let validatedAt, let isOfflineGrace):
            activeCard(planName: planName, validatedAt: validatedAt, isOfflineGrace: isOfflineGrace)
        case .trial(let days):
            trialCard(days: days)
        case .expired:
            expiredCard
        case .invalid(let reason):
            invalidCard(reason: reason)
        case .checking:
            checkingCard
        }
    }

    private func activeCard(planName: String?, validatedAt: Date, isOfflineGrace: Bool) -> some View {
        let displayName = {
            let trimmed = planName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? "Pro" : trimmed
        }()

        return MenuCard {
            HStack {
                HStack(spacing: 9) {
                    Circle()
                        .fill(isOfflineGrace ? .orange : .green)
                        .frame(width: 7, height: 7)
                    Text(displayName)
                        .font(.headline.weight(.semibold))
                }

                Spacer()

                statusPill(text: isOfflineGrace ? "Offline Grace" : "Active", tint: isOfflineGrace ? .orange : .green)

                Button("Manage") {
                    Task { @MainActor in
                        await licenseService.openManageSubscription()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(licenseService.isLoading)
            }

            NativeMenuDivider()

            if let email = licenseService.storedEmail {
                Text("Signed in as \(email)")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(MenuTheme.subtleText)
            }

            Text("Last validation: \(validationText(for: validatedAt))")
                .font(.footnote.weight(.medium))
                .foregroundStyle(MenuTheme.subtleText)
        }
        .background(cardTint(isOfflineGrace ? .orange : .green))
    }

    private func trialCard(days: Int) -> some View {
        MenuCard {
            HStack {
                Text("Trial Active")
                    .font(.headline.weight(.semibold))

                Spacer()

                statusPill(text: "\(days)d left", tint: .orange)

                Button("Upgrade") {
                    handleUpgradeClick()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            ProgressView(value: trialProgress(days: days))
                .tint(.orange)
        }
        .background(cardTint(.orange))
    }

    private var expiredCard: some View {
        MenuCard {
            HStack {
                Text("Trial Expired")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.red)

                Spacer()

                statusPill(text: "Expired", tint: .red)
            }

            ProgressView(value: 1)
                .tint(.red)

            HStack {
                Spacer()

                Button("Upgrade") {
                    handleUpgradeClick()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.red)
            }
        }
        .background(cardTint(.red))
    }

    private func invalidCard(reason: String) -> some View {
        MenuCard {
            HStack {
                Text("Subscription Issue")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.red)

                Spacer()

                statusPill(text: "Action needed", tint: .red)
            }

            Text(reason)
                .font(.footnote.weight(.medium))
                .foregroundStyle(MenuTheme.subtleText)

            HStack {
                Spacer()

                Button("Manage") {
                    Task { @MainActor in
                        await licenseService.openManageSubscription()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.red)
            }
        }
        .background(cardTint(.red))
    }

    private var checkingCard: some View {
        MenuCard {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Checking subscription")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(MenuTheme.subtleText)
            }
        }
    }

    private var subscribePrompt: some View {
        MenuCard {
            HStack {
                Text("Subscribe — $8.99/month")
                    .font(.headline.weight(.semibold))

                Spacer()

                Button {
                    showSubscribePrompt = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(MenuTheme.subtleText)
                }
                .buttonStyle(.plain)
            }

            if let email = licenseService.storedEmail {
                Text("Signed in as \(email). Click below to subscribe via Stripe.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(MenuTheme.subtleText)
            }

            HStack {
                Button("Sign out") {
                    licenseService.signOut()
                    showSubscribePrompt = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .underline()

                Spacer()

                Button("Subscribe") {
                    Task { @MainActor in
                        await licenseService.openUpgrade()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(licenseService.isLoading)
            }

            if let error = licenseService.lastError {
                Text(error)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Actions

    private func handleUpgradeClick() {
        if licenseService.isSignedIn {
            showSubscribePrompt = true
        } else {
            showSignIn = true
        }
    }

    // MARK: - Helpers

    private func validationText(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func cardTint(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(MenuTheme.tintedSurface(color))
    }

    private func statusPill(text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(MenuTheme.tintedSurface(tint), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(MenuTheme.tintedBorder(tint), lineWidth: 1)
            )
            .foregroundStyle(tint)
    }

    private func trialProgress(days: Int) -> Double {
        let clamped = max(0, min(14, days))
        return Double(clamped) / 14.0
    }
}
