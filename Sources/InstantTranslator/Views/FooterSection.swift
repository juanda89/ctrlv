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
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MenuTheme.subtleText)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(MenuTheme.controlFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(MenuTheme.controlBorder, lineWidth: 1)
                    )
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
