import ControlVCore

import SwiftUI

@MainActor
struct SignInView: View {
    @Bindable var licenseService: LicenseService
    let onClose: () -> Void

    @State private var emailInput: String = ""
    @State private var codeInput: String = ""
    @State private var localMessage: String?

    var body: some View {
        MenuCard {
            HStack {
                Text(headerTitle)
                    .font(.headline.weight(.semibold))

                Spacer()

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(MenuTheme.subtleText)
                }
                .buttonStyle(.plain)
            }

            if licenseService.pendingMagicCodeEmail == nil {
                emailStep
            } else {
                codeStep
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
    }

    // MARK: - Steps

    @ViewBuilder
    private var emailStep: some View {
        Text("Enter your email to continue. We'll send you a 6-digit code.")
            .font(.footnote.weight(.medium))
            .foregroundStyle(MenuTheme.subtleText)

        VStack(alignment: .leading, spacing: 6) {
            Text("Email")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(MenuTheme.subtleText)
            NativeTextField(
                text: $emailInput,
                placeholder: "you@example.com",
                autoFocus: true,
                onSubmit: { submitEmail() }
            )
            .frame(height: 24)
        }

        HStack {
            Spacer()
            Button("Continue") {
                submitEmail()
            }
            .buttonStyle(.borderedProminent)
            .tint(MenuTheme.cyan)
            .disabled(licenseService.isLoading || emailInput.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    @ViewBuilder
    private var codeStep: some View {
        Text("We sent a code to \(licenseService.pendingMagicCodeEmail ?? "your email").")
            .font(.footnote.weight(.medium))
            .foregroundStyle(MenuTheme.subtleText)

        VStack(alignment: .leading, spacing: 6) {
            Text("6-digit code")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(MenuTheme.subtleText)
            NativeTextField(
                text: $codeInput,
                placeholder: "123456",
                keyboardType: .numeric,
                maxLength: 6,
                autoFocus: true,
                onSubmit: { submitCode() }
            )
            .frame(height: 24)
        }

        HStack {
            Button("Use a different email") {
                licenseService.cancelPendingSignIn()
                codeInput = ""
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .underline()

            Spacer()

            Button("Verify") {
                submitCode()
            }
            .buttonStyle(.borderedProminent)
            .tint(MenuTheme.cyan)
            .disabled(licenseService.isLoading || codeInput.count != 6)
        }
    }

    // MARK: - Helpers

    private var headerTitle: String {
        licenseService.pendingMagicCodeEmail == nil ? "Sign in to upgrade" : "Verify your email"
    }

    private func submitEmail() {
        let trimmed = emailInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        Task { @MainActor in
            localMessage = nil
            let ok = await licenseService.requestMagicCode(email: trimmed)
            if ok {
                emailInput = ""
            }
        }
    }

    private func submitCode() {
        guard codeInput.count == 6 else { return }
        Task { @MainActor in
            localMessage = nil
            let ok = await licenseService.verifyMagicCode(codeInput)
            if ok {
                codeInput = ""
                onClose()
            }
        }
    }
}
