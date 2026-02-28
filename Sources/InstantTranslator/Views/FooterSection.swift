import SwiftUI

@MainActor
struct FooterSection: View {
    @Bindable var translatorVM: TranslatorViewModel
    @Bindable var updateService: UpdateService
    let onOpenFeedback: () -> Void
    let onCheckForUpdates: () -> Void
    let onShowAbout: () -> Void

    @State private var showDebugSheet = false

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
                Button("Debug") {
                    showDebugSheet = true
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
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
        }
        .sheet(isPresented: $showDebugSheet) {
            DebugSheet(translatorVM: translatorVM, updateService: updateService)
        }
    }

    private var appVersionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "v\(version ?? "1.0.0")"
    }
}
