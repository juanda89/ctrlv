import SwiftUI

@MainActor
struct StatusSection: View {
    @Bindable var licenseService: LicenseService

    @State private var showLicenseSheet = false
    @State private var licenseKeyInput = ""
    @State private var localMessage: String?
    @FocusState private var isLicenseFieldFocused: Bool

    var body: some View {
        if showLicenseSheet {
            inlineLicenseForm
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
            return trimmed.isEmpty ? "License Active" : trimmed
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
            }

            NativeMenuDivider()

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
                    prepareLicenseSheet()
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
                    prepareLicenseSheet()
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
                Text("License Invalid")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.red)

                Spacer()

                statusPill(text: "Invalid", tint: .red)
            }

            Text(reason)
                .font(.footnote.weight(.medium))
                .foregroundStyle(MenuTheme.subtleText)

            HStack {
                Spacer()

                Button("Upgrade") {
                    prepareLicenseSheet()
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
                Text("Checking license")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(MenuTheme.subtleText)
            }
        }
    }

    private var inlineLicenseForm: some View {
        MenuCard {
            HStack {
                Text("Enter License Key")
                    .font(.headline.weight(.semibold))

                Spacer()

                Button {
                    showLicenseSheet = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(MenuTheme.subtleText)
                }
                .buttonStyle(.plain)
            }

            Text("Paste your Lemon Squeezy license key to activate this device.")
                .font(.footnote.weight(.medium))
                .foregroundStyle(MenuTheme.subtleText)

            VStack(alignment: .leading, spacing: 6) {
                Text("License Key")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(MenuTheme.subtleText)
                TextField("XXXX-XXXX-XXXX-XXXX", text: $licenseKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .focused($isLicenseFieldFocused)
            }

            HStack {
                Button("Get your license key") {
                    licenseService.openUpgrade()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .underline()

                Spacer()

                Button("Activate") {
                    Task { @MainActor in
                        localMessage = nil
                        let ok = await licenseService.submitLicenseKey(licenseKeyInput)
                        if ok {
                            showLicenseSheet = false
                        } else if licenseService.state.canTranslate {
                            localMessage = "License key not active yet. Trial is still available."
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(licenseService.isLoading)
            }

            if let message = localMessage {
                Text(message)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(MenuTheme.subtleText)
            } else if let error = licenseService.lastError {
                Text(error)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.red)
            }
        }
        .onAppear {
            isLicenseFieldFocused = true
        }
        .onDisappear {
            showLicenseSheet = false
        }
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
