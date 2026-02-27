import SwiftUI

struct FooterSection: View {
    let onOpenFeedback: () -> Void
    let onCheckForUpdates: () -> Void
    let onShowAbout: () -> Void

    var body: some View {
        HStack {
            Spacer()

            Menu {
                Button("Feedback") {
                    onOpenFeedback()
                }
                Button("About") {
                    onShowAbout()
                }
                Button("Check for Updates") {
                    onCheckForUpdates()
                }
                Divider()
                Text(appVersionLabel)
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
