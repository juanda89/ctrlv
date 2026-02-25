import SwiftUI

struct StatusSection: View {
    @Bindable var licenseService: LicenseService

    @State private var showLicenseSheet = false
    @State private var licenseKeyInput = ""
    @State private var localMessage: String?

    var body: some View {
        section
            .sheet(isPresented: $showLicenseSheet) {
                licenseSheet
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
            return trimmed.isEmpty ? "License Active" : trimmed
        }()

        return MenuCard {
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(isOfflineGrace ? .orange : .green)
                        .frame(width: 7, height: 7)
                    Text(displayName)
                        .font(.system(size: 15, weight: .semibold))
                }

                Spacer()

                statusPill(text: isOfflineGrace ? "Offline Grace" : "Active", tint: isOfflineGrace ? .orange : .green)
            }

            Divider()
                .overlay((isOfflineGrace ? Color.orange : Color.green).opacity(0.25))

            Text("Last validation: \(validationText(for: validatedAt))")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            HStack {
                Button("Manage") {
                    licenseService.openManageSubscription()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .tint(.green)

                Spacer()

                Button("Deactivate") {
                    Task {
                        localMessage = nil
                        _ = await licenseService.deactivateCurrentLicense()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .background(cardTint(isOfflineGrace ? .orange : .green))
    }

    private func trialCard(days: Int) -> some View {
        MenuCard {
            HStack {
                Text("Trial Active")
                    .font(.system(size: 15, weight: .semibold))

                Spacer()

                statusPill(text: "\(days)d left", tint: .orange)
            }

            ProgressView(value: trialProgress(days: days))
                .tint(.orange)

            HStack {
                Label("License", systemImage: "key.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Upgrade") {
                    licenseService.openUpgrade()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)

                Button("Enter Key") {
                    prepareLicenseSheet()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .background(cardTint(.orange))
    }

    private var expiredCard: some View {
        MenuCard {
            HStack {
                Text("Trial Expired")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.red)

                Spacer()

                statusPill(text: "Expired", tint: .red)
            }

            ProgressView(value: 1)
                .tint(.red)

            HStack {
                Label("License", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Upgrade") {
                    licenseService.openUpgrade()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .tint(.red)

                Button("Enter Key") {
                    prepareLicenseSheet()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .background(cardTint(.red))
    }

    private func invalidCard(reason: String) -> some View {
        MenuCard {
            HStack {
                Text("License Invalid")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.red)

                Spacer()

                statusPill(text: "Invalid", tint: .red)
            }

            Text(reason)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            HStack {
                Button("Upgrade") {
                    licenseService.openUpgrade()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .tint(.red)

                Spacer()

                Button("Enter Key") {
                    prepareLicenseSheet()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .background(cardTint(.red))
    }

    private var checkingCard: some View {
        MenuCard {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Checking license")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var licenseSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enter License Key")
                .font(.system(size: 18, weight: .bold))

            Text("Paste your Lemon Squeezy license key to activate this device.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("License Key")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("XXXX-XXXX-XXXX-XXXX", text: $licenseKeyInput)
                    .textFieldStyle(.roundedBorder)
            }

            Button {
                Task {
                    localMessage = nil
                    let ok = await licenseService.submitLicenseKey(licenseKeyInput)
                    if ok {
                        showLicenseSheet = false
                    } else if licenseService.state.canTranslate {
                        localMessage = "License key not active yet. Trial is still available."
                    }
                }
            } label: {
                Text("Activate")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(licenseService.isLoading)

            HStack {
                Button("Upgrade") {
                    licenseService.openUpgrade()
                }
                .buttonStyle(.bordered)

                Spacer()

                if licenseService.storedLicenseKey != nil {
                    Button("Clear Stored Key") {
                        licenseService.clearStoredLicense()
                        localMessage = "Stored key removed."
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let message = localMessage {
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            } else if let error = licenseService.lastError {
                Text(error)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    private func prepareLicenseSheet() {
        licenseKeyInput = licenseService.storedLicenseKey ?? ""
        localMessage = nil
        showLicenseSheet = true
    }

    private func validationText(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func cardTint(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(color.opacity(0.07))
    }

    private func statusPill(text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }

    private func trialProgress(days: Int) -> Double {
        let clamped = max(0, min(14, days))
        return Double(clamped) / 14.0
    }
}
