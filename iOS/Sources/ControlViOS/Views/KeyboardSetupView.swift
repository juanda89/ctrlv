import SwiftUI

/// One-time setup for translating in any app. Two paths: the system
/// Translate menu (Control-V as default translation app, iOS 18.4+) and the
/// Control-V keyboard (any iOS, also works on text you just typed).
/// Shown on first launch and reachable from Translate and Account.
struct KeyboardSetupView: View {
    let onDone: () -> Void

    private var supportsDefaultTranslation: Bool {
        if #available(iOS 18.4, *) { return true } else { return false }
    }

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

                    if supportsDefaultTranslation {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Label("Select → Translate → Replace", systemImage: "text.cursor").font(.headline)
                                Spacer()
                                Text("RECOMMENDED").font(.caption2.weight(.bold)).foregroundStyle(Brand.blue)
                            }
                            StepRow(number: 1, title: "Make Control-V your translator", detail: "Settings → Apps → Default Apps → Translation → Control-V.")
                            StepRow(number: 2, title: "Select text in any app", detail: "Messages, WhatsApp, Mail, Safari… tap the selection, then Translate.")
                            StepRow(number: 3, title: "Tap Replace", detail: "Your text is swapped for the translation. If the text isn't editable, tap Copy instead.")
                        }
                        .padding(18)
                        .glassCard(24)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Label(supportsDefaultTranslation ? "Or use the keyboard" : "Use the Control-V keyboard", systemImage: "keyboard").font(.headline)
                        Text("Also translates what you just typed, with nothing selected.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        StepRow(number: 1, title: "Add the keyboard", detail: "Settings → General → Keyboard → Keyboards → Add New Keyboard → Control-V.")
                        StepRow(number: 2, title: "Allow Full Access", detail: "Needed to reach the translation service; nothing you type is logged or stored.")
                        StepRow(number: 3, title: "Translate & Replace", detail: "Hold the globe key, pick Control-V, tap the button.")
                    }
                    .padding(18)
                    .glassCard(24)

                    HStack(spacing: 6) {
                        Image(systemName: "info.circle").foregroundStyle(.secondary)
                        Text("Sharing text to Control-V from any app also works for a quick copy.")
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
