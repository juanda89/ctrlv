import SwiftUI

/// Blocking onboarding: Control-V's whole point is translating inside other
/// apps, and nothing in here works until iOS is told to let it. The screen
/// shows both ways, what each one costs, and exactly what using it looks like.
///
/// There is no "skip": the sheet closes by itself the moment either path is
/// detected. The extensions record that they ran (`SetupState`), so no
/// confirmation is ever asked of the user.
struct KeyboardSetupView: View {
    let onDone: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var keyboardReady = SetupState.keyboardReady
    @State private var menuReady = SetupState.translationProviderReady
    @State private var checkedAndMissing = false

    private var anyReady: Bool { keyboardReady || menuReady }
    private var supportsDefaultTranslation: Bool {
        if #available(iOS 18.4, *) { return true } else { return false }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if supportsDefaultTranslation {
                option(
                    title: "From the Translate menu",
                    symbol: "text.cursor",
                    isReady: menuReady,
                    steps: [.init("Select text", symbol: "text.cursor"), .init("Tap Translate", symbol: "globe"), .init("Tap Replace", symbol: "arrow.left.arrow.right")],
                    path: "Settings › Apps › Default Apps › Translation › Control-V",
                    confirm: { SetupState.confirmTranslationProvider(); refresh() }
                )
            }
            option(
                title: "From your keyboard",
                symbol: "keyboard",
                isReady: keyboardReady,
                steps: [.init("Write or select", symbol: "keyboard"), .init("Tap the V key", brandKey: true), .init("It's replaced", symbol: "checkmark.circle")],
                path: "Settings › General › Keyboard › Keyboards › Control-V › Allow Full Access",
                confirm: { SetupState.confirmKeyboard(); refresh() }
            )

            Label("Full Access only sends the text you pick. Nothing you type is logged or stored.", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if checkedAndMissing {
                Label("Not detected yet. Open the Control-V keyboard once in any app, or translate something with the Translate menu.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AuroraBackground())
        .safeAreaInset(edge: .bottom) { footer }
        .interactiveDismissDisabled(!anyReady)
        .task(id: scenePhase) { await watchForChanges() }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 12) {
            BrandMark(size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(anyReady ? "You're set" : "Two ways to translate")
                    .font(.title2.weight(.bold))
                Text(anyReady
                     ? "Control-V now works inside your other apps."
                     : "Control-V works inside other apps. Turn on either one, or both.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    struct Step {
        let caption: String
        var symbol: String = ""
        /// Draws the Control-V key itself instead of an SF Symbol.
        var brandKey = false

        init(_ caption: String, symbol: String) { self.caption = caption; self.symbol = symbol }
        init(_ caption: String, brandKey: Bool) { self.caption = caption; self.brandKey = brandKey }
    }

    private func option(title: String, symbol: String, isReady: Bool, steps: [Step], path: String, confirm: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: isReady ? "checkmark.circle.fill" : symbol)
                    .font(.title3)
                    .foregroundStyle(isReady ? Color.green : Brand.blue)
                Text(title).font(.body.weight(.semibold))
                Spacer(minLength: 0)
                if isReady {
                    Text("On")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.15), in: Capsule())
                } else {
                    // Being the default translation app is invisible to us, so
                    // the user can just say so.
                    Button("It's on", action: confirm)
                        .font(.caption2.weight(.bold))
                        .buttonStyle(.plain)
                        .foregroundStyle(Brand.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Brand.blue.opacity(0.12), in: Capsule())
                }
            }

            stepStrip(steps)

            Text(path)
                .font(.caption).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(18)
    }

    /// What using it actually looks like, so the value is obvious before the
    /// user is sent into Settings.
    private func stepStrip(_ steps: [Step]) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                VStack(spacing: 5) {
                    Group {
                        if step.brandKey {
                            Text("V")
                                .font(.system(size: 19, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(Brand.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        } else {
                            Image(systemName: step.symbol)
                                .font(.subheadline)
                                .foregroundStyle(Brand.blue)
                                .frame(width: 38, height: 38)
                                .background(Brand.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        }
                    }
                    Text(step.caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)

                if index < steps.count - 1 {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 18)
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            } label: { Label("Open Settings", systemImage: "gear") }
            .buttonStyle(PrimaryButtonStyle())

            if anyReady {
                Button("Start translating", action: onDone)
                    .font(.subheadline.weight(.semibold))
            } else {
                Button("I already turned it on") {
                    refresh()
                    checkedAndMissing = !anyReady
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            }
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
            if anyReady {
                checkedAndMissing = false
                if !wasReady {
                    try? await Task.sleep(for: .seconds(1.4))
                    onDone()
                    return
                }
            }
        }
    }

    private func refresh() {
        keyboardReady = SetupState.keyboardReady
        menuReady = SetupState.translationProviderReady
    }
}
