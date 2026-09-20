import SwiftUI

/// One-time setup for translating outside the app. Two independent paths, each
/// enough on its own: the system Translate menu and the Control-V keyboard.
///
/// The screen checks what is already on instead of asking the user to confirm:
/// the extensions record that they ran, so a path flips to "Ready" by itself
/// and the sheet closes when the first one does.
struct KeyboardSetupView: View {
    let onDone: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var keyboardReady = SetupState.keyboardReady
    @State private var menuReady = SetupState.translationProviderReady

    private var anyReady: Bool { keyboardReady || menuReady }
    private var supportsDefaultTranslation: Bool {
        if #available(iOS 18.4, *) { return true } else { return false }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            VStack(spacing: 12) {
                if supportsDefaultTranslation {
                    option(
                        title: "Translate menu",
                        detail: "Select text in any app, tap Translate, tap Replace.",
                        path: "Settings › Apps › Default Apps › Translation",
                        symbol: "text.cursor",
                        isReady: menuReady
                    )
                }
                option(
                    title: "Control-V keyboard",
                    detail: "Adds a Translate button to your keyboard, so you never switch apps.",
                    path: "Settings › General › Keyboard › Keyboards › Allow Full Access",
                    symbol: "keyboard",
                    isReady: keyboardReady
                )
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AuroraBackground())
        .safeAreaInset(edge: .bottom) { footer }
        .task(id: scenePhase) { await watchForChanges() }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                BrandMark(size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(anyReady ? "You're set" : "Translate in any app")
                        .font(.title2.weight(.bold))
                    Text(anyReady ? "Control-V is ready to use outside the app." : "Turn on either one. You only need one.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func option(title: String, detail: String, path: String, symbol: String, isReady: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isReady ? "checkmark.circle.fill" : symbol)
                .font(.title3)
                .foregroundStyle(isReady ? Color.green : Brand.blue)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title).font(.body.weight(.semibold))
                    Spacer(minLength: 0)
                    Text(isReady ? "Ready" : "Off")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(isReady ? Color.green : Color.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background((isReady ? Color.green : Color.secondary).opacity(0.14), in: Capsule())
                }
                Text(detail)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(path)
                    .font(.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(18)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            } label: { Label("Open Settings", systemImage: "gear") }
            .buttonStyle(PrimaryButtonStyle())

            Button(anyReady ? "Done" : "Later", action: onDone)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }

    // MARK: - Live status

    /// Polls while the sheet is on screen. iOS offers no notification for
    /// "the user enabled your keyboard", and the extensions can only record it
    /// the next time they run, so a short poll is the only way to react.
    private func watchForChanges() async {
        refresh()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1.5))
            let wasReady = anyReady
            refresh()
            if anyReady, !wasReady {
                try? await Task.sleep(for: .seconds(1.2))
                onDone()
                return
            }
        }
    }

    private func refresh() {
        keyboardReady = SetupState.keyboardReady
        menuReady = SetupState.translationProviderReady
    }
}
