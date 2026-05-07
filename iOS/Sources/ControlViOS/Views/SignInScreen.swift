import ControlVCore
import SwiftUI

struct SignInScreen: View {
    @Environment(LicenseService.self) private var license
    @Environment(\.dismiss) private var dismiss
    @State private var email: String = ""
    @State private var code: String = ""
    @FocusState private var fieldFocus: Field?

    enum Field { case email, code }

    var body: some View {
        Form {
            if license.pendingMagicCodeEmail == nil {
                Section {
                    TextField("you@example.com", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .focused($fieldFocus, equals: .email)
                } header: {
                    Text("Email")
                } footer: {
                    Text("We'll send you a 6-digit code. No password required.")
                }

                Section {
                    Button("Send code") {
                        Task { await requestCode() }
                    }
                    .disabled(license.isLoading || email.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else {
                Section {
                    TextField("123456", text: $code)
                        .keyboardType(.numberPad)
                        .focused($fieldFocus, equals: .code)
                        .onChange(of: code) { _, new in
                            let filtered = String(new.filter(\.isNumber).prefix(6))
                            if filtered != new { code = filtered }
                        }
                } header: {
                    Text("Enter the code")
                } footer: {
                    Text("Sent to \(license.pendingMagicCodeEmail ?? email).")
                }

                Section {
                    Button("Verify") {
                        Task { await verifyCode() }
                    }
                    .disabled(license.isLoading || code.count != 6)

                    Button("Use a different email", role: .cancel) {
                        license.cancelPendingSignIn()
                        code = ""
                    }
                }
            }

            if let error = license.lastError {
                Section {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Sign in")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { fieldFocus = license.pendingMagicCodeEmail == nil ? .email : .code }
    }

    private func requestCode() async {
        let ok = await license.requestMagicCode(email: email)
        if ok { fieldFocus = .code }
    }

    private func verifyCode() async {
        let ok = await license.verifyMagicCode(code)
        if ok { dismiss() }
    }
}
