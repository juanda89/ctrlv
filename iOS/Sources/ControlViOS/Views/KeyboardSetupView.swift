import SwiftUI

/// Blocking onboarding: Control-V's whole point is translating inside other
/// apps, and nothing in here works until iOS is told to let it. The screen
/// shows both ways, the exact Settings path for each, and closes by itself
/// the moment either one is detected.
///
/// What is detected and what is taken on the user's word (`SetupState`): the
/// keyboard's presence in Settings is read directly; Full Access and the
/// Translate menu are reported by the extensions when they run; and both
/// cards keep an "It's on" button, because being the default translation app
/// is invisible to us until it is used.
struct KeyboardSetupView: View {
    let onDone: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var keyboard = SetupState.keyboardStatus
    @State private var menuReady = SetupState.translationProviderReady
    @State private var checkedAndMissing = false
    @State private var sampleText = "Hola, ¿cómo va todo por allá? Escríbeme cuando puedas."
    @FocusState private var fieldFocused: Bool

    private var anyReady: Bool { keyboard == .ready || menuReady }
    private var supportsDefaultTranslation: Bool {
        if #available(iOS 18.4, *) { return true } else { return false }
    }
    /// Added in Settings but not seen running yet: the one moment a field
    /// helps, because opening the keyboard here is what checks Full Access.
    private var showsTryField: Bool { keyboard == .addedNotOpened || keyboard == .addedNoFullAccess }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if supportsDefaultTranslation { menuCard }
                keyboardCard
                if showsTryField { tryCard }
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
            }
            .padding(22)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AuroraBackground())
        .safeAreaInset(edge: .bottom) { footer }
        .interactiveDismissDisabled(!anyReady)
        .task(id: scenePhase) { await watchForChanges() }
        .onReceive(NotificationCenter.default.publisher(for: .controlVSetupChanged)) { _ in refresh() }
    }

    // MARK: - Header

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

    // MARK: - Cards

    private var menuCard: some View {
        card(
            title: "From the Translate menu",
            symbol: "text.cursor",
            pill: menuReady ? .on : .init(text: "Not yet", color: .secondary),
            steps: [.init("Select text", symbol: "text.cursor"), .init("Tap Translate", symbol: "globe"), .init("Tap Replace", symbol: "arrow.left.arrow.right")],
            detail: "Settings › Apps › Default Apps › Translation › Control-V",
            confirm: menuReady ? nil : { SetupState.confirmTranslationProvider(); refresh() }
        ) {
            if !menuReady {
                Button {
                    if #available(iOS 18.3, *) {
                        open(UIApplication.openDefaultApplicationsSettingsURLString)
                    } else {
                        open(UIApplication.openSettingsURLString)
                    }
                } label: { Label("Open Default Apps", systemImage: "gear") }
                .buttonStyle(GlassButtonStyle())
            }
        }
    }

    private var keyboardCard: some View {
        card(
            title: "From your keyboard",
            symbol: "keyboard",
            pill: keyboardPill,
            steps: [.init("Write or select", symbol: "keyboard"), .init("Tap the V key", brandKey: true), .init("It's replaced", symbol: "checkmark.circle")],
            detail: keyboardDetail,
            confirm: keyboard == .ready ? nil : { SetupState.confirmKeyboard(); refresh() }
        ) {
            if keyboard != .ready {
                Button {
                    open(UIApplication.openSettingsURLString)
                } label: { Label(keyboard == .notAdded ? "Add it in Settings" : "Open Settings", systemImage: "gear") }
                .buttonStyle(GlassButtonStyle())
            }
        }
    }

    private var keyboardPill: Pill {
        switch keyboard {
        case .notAdded: return .init(text: "Not added", color: .secondary)
        case .addedNotOpened: return .init(text: "Added", color: .orange)
        case .addedNoFullAccess: return .init(text: "No Full Access", color: .orange)
        case .ready: return .on
        }
    }

    private var keyboardDetail: String {
        switch keyboard {
        case .notAdded:
            return "Settings › General › Keyboard › Keyboards › Add New Keyboard › Control-V › Allow Full Access"
        case .addedNotOpened:
            return "Added. Open it once below to check Full Access: tap the text, hold the globe key and pick Control-V."
        case .addedNoFullAccess:
            return "Full Access is off, so it can type but not translate. Turn it on under Keyboards › Control-V, then open the keyboard again below."
        case .ready:
            return "Works. Tap the V key next to the space bar to translate what you typed."
        }
    }

    private var tryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Try it here")
            TextEditor(text: $sampleText)
                .font(.body)
                .frame(minHeight: 64, maxHeight: 96)
                .padding(8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .focused($fieldFocused)
                .accessibilityIdentifier("setup.testField")
            Text("Tap the text, hold the globe key and pick Control-V.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(18)
    }

    // MARK: - Card pieces

    struct Pill {
        let text: String
        let color: Color
        static let on = Pill(text: "On", color: .green)
    }

    struct Step {
        let caption: String
        var symbol: String = ""
        /// Draws the Control-V key itself instead of an SF Symbol.
        var brandKey = false

        init(_ caption: String, symbol: String) { self.caption = caption; self.symbol = symbol }
        init(_ caption: String, brandKey: Bool) { self.caption = caption; self.brandKey = brandKey }
    }

    private func card<Action: View>(title: String, symbol: String, pill: Pill, steps: [Step], detail: String, confirm: (() -> Void)?, @ViewBuilder action: () -> Action) -> some View {
        let isOn = pill.text == Pill.on.text
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: isOn ? "checkmark.circle.fill" : symbol)
                    .font(.title3)
                    .foregroundStyle(isOn ? Color.green : Brand.blue)
                Text(title).font(.body.weight(.semibold))
                Spacer(minLength: 0)
                Text(pill.text)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(pill.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(pill.color.opacity(0.15), in: Capsule())
            }
            stepStrip(steps)
            Text(detail)
                .font(.caption)
                .foregroundStyle(isOn ? Color.secondary : Color.primary.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                action()
                if let confirm {
                    // The status above is what was observed; this is the
                    // user's word, for what cannot be observed.
                    Button(action: confirm) { Label("It's on", systemImage: "checkmark") }
                        .buttonStyle(GlassButtonStyle())
                }
            }
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
                open(UIApplication.openSettingsURLString)
            } label: { Label("Open Settings", systemImage: "gear") }
            .buttonStyle(PrimaryButtonStyle())

            if anyReady {
                Button("Done", action: onDone)
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

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Live status

    /// Polls while the sheet is on screen. iOS offers no notification for
    /// "the user enabled your keyboard", so a short poll is the only way to
    /// react; it restarts on every scene change so coming back from Settings
    /// refreshes at once.
    private func watchForChanges() async {
        refresh()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            let wasReady = anyReady
            refresh()
            if anyReady, !wasReady {
                checkedAndMissing = false
                fieldFocused = false
                try? await Task.sleep(for: .seconds(1.4))
                onDone()
                return
            }
        }
    }

    private func refresh() {
        keyboard = SetupState.keyboardStatus
        menuReady = SetupState.translationProviderReady
        if anyReady { checkedAndMissing = false }
    }
}
