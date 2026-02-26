import SwiftUI

@MainActor
struct UpdateFailureSheet: View {
    @Bindable var updateService: UpdateService
    @State private var copiedDiagnostics = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Update needs manual install")
                .font(.system(size: 17, weight: .bold))

            Text(updateService.lastUpdateErrorSummary ?? "Automatic update failed.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            if let details = updateService.lastUpdateErrorDetails {
                ScrollView {
                    Text(details)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 72, maxHeight: 116)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.primary.opacity(0.06))
                )
            }

            HStack(spacing: 8) {
                Button("Download latest .dmg") {
                    updateService.openLatestDMG()
                    updateService.dismissManualUpdateFallback()
                }
                .buttonStyle(.borderedProminent)

                Button("Open install guide") {
                    updateService.openInstallGuide()
                    updateService.dismissManualUpdateFallback()
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                Button(copiedDiagnostics ? "Diagnostics copied" : "Copy diagnostics") {
                    copiedDiagnostics = true
                    updateService.copyDiagnosticsToClipboard()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Close") {
                    updateService.dismissManualUpdateFallback()
                }
                .buttonStyle(.plain)
            }
            .font(.system(size: 12, weight: .medium))
        }
        .padding(16)
        .frame(width: 420)
        .onDisappear {
            copiedDiagnostics = false
        }
    }
}
