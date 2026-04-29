import SwiftUI

@MainActor
struct SignInView: View {
    @Bindable var licenseService: LicenseService
    let onClose: () -> Void

    @State private var emailInput: String = ""
    @State private var codeInput: String = ""
    @State private var localMessage: String?
    @FocusState private var emailFocused: Bool
    @FocusState private var codeFocused: Bool

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
        .onAppear {
            if licenseService.pendingMagicCodeEmail == nil {
                emailFocused = true
            } else {
                codeFocused = true
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
            TextField("you@example.com", text: $emailInput)
                .textFieldStyle(.roundedBorder)
                .focused($emailFocused)
                .onSubmit { submitEmail() }
        }

        HStack {
            Spacer()
            Button("Continue") {
                submitEmail()
            }
            .buttonStyle(.borderedProminent)
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
            TextField("123456", text: $codeInput)
                .textFieldStyle(.roundedBorder)
                .focused($codeFocused)
                .onChange(of: codeInput) { _, newValue in
                    let filtered = newValue.filter { $0.isNumber }
                    if filtered != newValue {
                        codeInput = filtered
                    }
                    if filtered.count > 6 {
                        codeInput = String(filtered.prefix(6))
                    }
                }
                .onSubmit { submitCode() }
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
                codeFocused = true
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
