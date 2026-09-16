import ControlVCore
import SwiftUI

/// Same backend as the Mac feedback: saved in app_feedback and emailed.
struct FeedbackSheet: View {
    @Environment(LicenseService.self) private var license
    @Environment(\.dismiss) private var dismiss
    let initialRating: Int?

    @State private var rating: Int?
    @State private var category: FeedbackCategory = .idea
    @State private var message = ""
    @State private var email = ""
    @State private var isSending = false
    @State private var didSend = false
    @State private var errorMessage: String?

    private var canSend: Bool { !isSending && (rating != nil || !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if didSend {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Thank you!").font(.largeTitle.weight(.bold))
                            Text("Every message is read by a person, and requests shape what gets built next.").foregroundStyle(.secondary)
                            Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle()).padding(.top, 8)
                        }
                    } else {
                        Text("Your feedback").font(.largeTitle.weight(.bold))
                        HStack(spacing: 8) {
                            ForEach(1...5, id: \.self) { star in
                                Button { rating = star } label: {
                                    Image(systemName: star <= (rating ?? 0) ? "star.fill" : "star")
                                        .font(.title).foregroundStyle(Color(red: 0.98, green: 0.74, blue: 0.20))
                                }.buttonStyle(.plain)
                            }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel(text: "What is it about?")
                            HStack(spacing: 8) {
                                ForEach(FeedbackCategory.allCases) { option in
                                    Chip(title: option.label, isSelected: option == category) { category = option }
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel(text: "Message")
                            TextField("What would make Control-V better for you?", text: $message, axis: .vertical)
                                .lineLimit(4...8).padding(14).glassCard(16)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel(text: "Email (optional, so we can reply)")
                            TextField("you@example.com", text: $email)
                                .textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                                .padding(14).glassCard(16)
                        }
                        if let errorMessage { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange) }
                        Button { Task { await send() } } label: {
                            if isSending { ProgressView().tint(.white) } else { Text("Send") }
                        }
                        .buttonStyle(PrimaryButtonStyle()).disabled(!canSend)
                    }
                }
                .padding(22)
            }
            .background(AuroraBackground())
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
            .onAppear {
                rating = initialRating
                if email.isEmpty { email = license.storedEmail ?? license.lastSignInEmail ?? "" }
            }
        }
    }

    private func send() async {
        isSending = true; errorMessage = nil; defer { isSending = false }
        let defaults = UserDefaults(suiteName: iOSSettingsStore.appGroup) ?? .standard
        let installID = DeviceIdentityStore(userDefaults: defaults).currentInstallID()
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let submission = FeedbackSubmission(
            rating: rating, category: category, message: message.trimmingCharacters(in: .whitespacesAndNewlines),
            contactEmail: trimmedEmail.contains("@") ? trimmedEmail : nil, installID: installID,
            sessionToken: license.storedSessionToken,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev",
            platform: "ios")
        do { try await FeedbackClient().submit(submission); withAnimation { didSend = true } }
        catch { errorMessage = error.localizedDescription }
    }
}
