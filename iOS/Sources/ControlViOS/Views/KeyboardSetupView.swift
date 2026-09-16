import SwiftUI

/// The one thing iOS users must do once to get the "translate in any app"
/// experience. Shown on first launch and reachable from Translate and Account.
struct KeyboardSetupView: View {
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        BrandMark(size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Translate in any app").font(.title2.weight(.bold))
                            Text("One-time setup, about a minute.").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        StepRow(number: 1, title: "Add the keyboard", detail: "Settings → General → Keyboard → Keyboards → Add New Keyboard → Control-V.")
                        StepRow(number: 2, title: "Allow Full Access", detail: "Tap Control-V in that list and turn on Allow Full Access. It's needed to reach the translation service; nothing you type is logged or stored.")
                        StepRow(number: 3, title: "Use it anywhere", detail: "Select text (or finish typing), hold the globe key, pick Control-V, tap Translate & Replace.")
                    }
                    .padding(18)
                    .glassCard(24)

                    HStack(spacing: 6) {
                        Image(systemName: "info.circle").foregroundStyle(.secondary)
                        Text("Apple doesn't let apps add a Translate button to the text selection menu, so the keyboard is the way to replace text in place. Sharing to Control-V also works for a quick copy.")
                            .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    } label: { Label("Open Settings", systemImage: "gear") }
                    .buttonStyle(PrimaryButtonStyle())

                    Button("Done", action: onDone)
                        .frame(maxWidth: .infinity)
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                }
                .padding(22)
            }
            .background(AuroraBackground())
        }
    }
}
