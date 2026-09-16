import ControlVCore
import SwiftUI

struct SignInScreen: View {
    @Environment(LicenseService.self) private var license
    @Environment(\.dismiss) private var dismiss
    @State private var email: String = ""
    @State private var code: String = ""
    @FocusState private var fieldFocus: Field?

    enum Field { case email, code }
    private var awaitingCode: Bool { license.pendingMagicCodeEmail != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    BrandMark(size: 48)
                    Text(awaitingCode ? "Check your email" : "Sign in").font(.largeTitle.weight(.bold))
                    Text(awaitingCode ? "We sent a 6-digit code to \(license.pendingMagicCodeEmail ?? email)." : "No password. We'll email you a 6-digit code.")
                        .font(.body).foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 10) {
                        if !awaitingCode {
                            TextField("you@example.com", text: $email)
                                .textContentType(.emailAddress).keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .font(.title3).padding(14).glassCard(16)
                                .focused($fieldFocus, equals: .email)
                                .submitLabel(.continue)
                                .onSubmit { Task { await requestCode() } }
                        } else {
                            TextField("123456", text: $code)
                                .keyboardType(.numberPad).textContentType(.oneTimeCode)
                                .font(.system(size: 34, weight: .semibold, design: .rounded)).kerning(6)
                                .multilineTextAlignment(.center)
                                .padding(14).glassCard(16)
                                .focused($fieldFocus, equals: .code)
                                .onChange(of: code) { _, new in
                                    let filtered = String(new.filter(\.isNumber).prefix(6))
                                    if filtered != new { code = filtered }
                                }
                        }
                    }

                    if let error = license.lastError {
                        Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote.weight(.medium)).foregroundStyle(.orange)
                    }

                    Button {
                        Task { awaitingCode ? await verifyCode() : await requestCode() }
                    } label: {
                        if license.isLoading { ProgressView().tint(.white) } else { Text(awaitingCode ? "Verify" : "Continue") }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(license.isLoading || (awaitingCode ? code.count != 6 : email.trimmingCharacters(in: .whitespaces).isEmpty))

                    if awaitingCode {
                        Button("Use a different email") { license.cancelPendingSignIn(); code = "" }
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(22)
            }
            .background(AuroraBackground())
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
            .onAppear {
                if email.isEmpty { email = license.lastSignInEmail ?? "" }
                fieldFocus = awaitingCode ? .code : .email
            }
        }
    }

    private func requestCode() async {
        if await license.requestMagicCode(email: email) { fieldFocus = .code }
    }

    private func verifyCode() async {
        if await license.verifyMagicCode(code) {
            AppGroupBridge.syncSessionToken(from: license)
            dismiss()
        }
    }
}
