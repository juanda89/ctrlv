import SwiftUI

@MainActor
@Observable
final class InstallerWindowState {
    var isInstalling = false
    var errorMessage: String?
}

@MainActor
struct InstallerWindowView: View {
    @Bindable var state: InstallerWindowState
    let destinationHint: String
    let onInstall: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.app.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(MenuTheme.blue)
                Text("Installing ctrl+v")
                    .font(.system(size: 20, weight: .bold))
            }

            Text("ctrl+v will install automatically and relaunch from:")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Text(destinationHint)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                )

            if state.isInstalling {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Installing...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else if let errorMessage = state.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            HStack {
                Button("Quit") {
                    onQuit()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(state.isInstalling ? "Installing..." : "Retry Install") {
                    onInstall()
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.isInstalling)
            }
        }
        .padding(18)
        .frame(width: 460, height: 260)
        .onAppear {
            guard !state.isInstalling else { return }
            onInstall()
        }
    }
}
