import SwiftUI

struct FooterSection: View {
    let onOpenFeedback: () -> Void
    let onCheckForUpdates: () -> Void
    let onShowAbout: () -> Void

    var body: some View {
        HStack {
            Button {
                onOpenFeedback()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 12, weight: .medium))
                    Text("Feedback")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Text(appVersionLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)

            Menu {
                Button("About") {
                    onShowAbout()
                }
                Button("Check for Updates") {
                    onCheckForUpdates()
                }
                Divider()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(Color.primary.opacity(0.08))
                    )
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
        }
    }

    private var appVersionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "v\(version ?? "1.0.0")"
    }
}
