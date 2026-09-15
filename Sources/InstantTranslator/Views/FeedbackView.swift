import ControlVCore
import SwiftUI

/// In-place feedback form (same swap pattern as SignInView / DebugSheet —
/// never a .sheet inside the popover).
@MainActor
struct FeedbackView: View {
    @State private var vm: FeedbackViewModel
    let onClose: () -> Void

    init(
        licenseService: LicenseService,
        translatorVM: TranslatorViewModel,
        initialRating: Int?,
        onClose: @escaping () -> Void
    ) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        _vm = State(initialValue: FeedbackViewModel(
            client: FeedbackClient(),
            tracker: translatorVM.feedbackPromptTracker,
            installID: translatorVM.installID,
            sessionToken: licenseService.storedSessionToken,
            contactEmail: licenseService.storedEmail ?? licenseService.lastSignInEmail,
            appVersion: version,
            initialRating: initialRating
        ))
        self.onClose = onClose
    }

    var body: some View {
        MenuCard {
            HStack {
                Text(vm.didSend ? "Thank you!" : "Your feedback")
                    .font(.headline.weight(.semibold))
                Spacer()
                Button { onClose() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(MenuTheme.subtleText)
                }
                .buttonStyle(.plain)
            }

            if vm.didSend {
                sentState
            } else {
                form
            }
        }
    }

    // MARK: - States

    private var sentState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Got it. Every message is read by a person, and requests shape what gets built next.")
                .font(.footnote.weight(.medium))
                .foregroundStyle(MenuTheme.subtleText)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Done") { onClose() }
                    .buttonStyle(.borderedProminent)
                    .tint(MenuTheme.cyan)
            }
        }
    }

    @ViewBuilder
    private var form: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Rating")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(MenuTheme.subtleText)
            StarRatingView(rating: $vm.rating, size: 22)
        }

        VStack(alignment: .leading, spacing: 6) {
            Text("What is it about?")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(MenuTheme.subtleText)
            HStack(spacing: 6) {
                ForEach(FeedbackCategory.allCases) { category in
                    categoryChip(category)
                }
            }
        }

        VStack(alignment: .leading, spacing: 6) {
            Text("Message")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(MenuTheme.subtleText)
            NativeControlSurface(cornerRadius: 12, horizontalPadding: 10, verticalPadding: 9) {
                TextField(
                    "What would make ctrl+v better for you?",
                    text: $vm.message,
                    axis: .vertical
                )
                .lineLimit(3...5)
                .textFieldStyle(.plain)
                .font(.subheadline)
            }
        }

        VStack(alignment: .leading, spacing: 6) {
            Text("Email (optional, so we can reply)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(MenuTheme.subtleText)
            NativeTextField(text: $vm.contactEmail, placeholder: "you@example.com")
                .frame(height: 24)
        }

        if let error = vm.lastError {
            Text(error)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }

        HStack {
            Spacer()
            Button(vm.isSending ? "Sending…" : "Send") {
                Task { await vm.send() }
            }
            .buttonStyle(.borderedProminent)
            .tint(MenuTheme.cyan)
            .disabled(!vm.canSend)
        }
    }

    private func categoryChip(_ category: FeedbackCategory) -> some View {
        let isSelected = vm.category == category
        return Button {
            vm.category = category
        } label: {
            Text(category.label)
                .font(.caption.weight(isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? MenuTheme.blue : .primary)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? MenuTheme.selectedFill : MenuTheme.controlFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSelected ? MenuTheme.selectedBorder : MenuTheme.controlBorder, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }
}
