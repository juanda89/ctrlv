import SwiftUI

/// Blocking onboarding: Control-V's whole point is translating inside other
/// apps, and nothing in here works until iOS is told to let it. The screen
/// shows both ways, the exact Settings path for each, and a text field where
/// either one can be tried on the spot.
///
/// There is no "skip" and no "I did it" button: the keyboard is looked up in
/// the enabled-keyboards list, and each extension records when it runs, so
/// the status shown here is the status observed (`SetupState`). The sheet
/// closes by itself the moment either path is detected.
struct KeyboardSetupView: View {
    let onDone: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var keyboard = SetupState.keyboardStatus
    @State private var menuReady = SetupState.translationProviderReady
    @State private var sampleText = "Hola, ¿cómo va todo por allá? Escríbeme cuando puedas."
    @State private var detectedMessage: String?
    @FocusState private var fieldFocused: Bool

    private var anyReady: Bool { keyboard == .ready || menuReady }
    private var supportsDefaultTranslation: Bool {
        if #available(iOS 18.4, *) { return true } else { return false }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if supportsDefaultTranslation { menuCard }
                keyboardCard
                checkCard
                Label("Full Access only sends the text you pick. Nothing you type is logged or stored.", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(22)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AuroraBackground())
        .safeAreaInset(edge: .bottom) { if anyReady { footer } }
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
                     : "Turn on one or both. Control-V checks them by itself.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Translate menu

    private var menuCard: some View {
        card(
            title: "From the Translate menu",
            symbol: "text.cursor",
            pill: menuReady ? .on : .init(text: "Not yet", color: .secondary),
            steps: [.init("Select text", symbol: "text.cursor"), .init("Tap Translate", symbol: "globe"), .init("Tap Replace", symbol: "arrow.left.arrow.right")],
            detail: menuReady
                ? "Works. Select text in any app, tap Translate, then Replace."
                : "Choose Control-V under Settings › Apps › Default Apps › Translation. Then select the text below and tap Translate to check it."
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

    // MARK: - Keyboard

    private var keyboardCard: some View {
        card(
            title: "From your keyboard",
            symbol: "keyboard",
            pill: keyboardPill,
            steps: [.init("Write or select", symbol: "keyboard"), .init("Tap the V key", brandKey: true), .init("It's replaced", symbol: "checkmark.circle")],
            detail: keyboardDetail
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
            return "Settings › General › Keyboard › Keyboards › Add New Keyboard › Control-V, then turn on Allow Full Access."
        case .addedNotOpened:
            return "Added. Now open it once below: tap the text, hold the globe key and pick Control-V."
        case .addedNoFullAccess:
            return "Full Access is off, so it can type but not translate. Turn it on under Keyboards › Control-V, then open the keyboard again below."
        case .ready:
            return "Works. Tap the V key next to the space bar to translate what you typed."
        }
    }

    // MARK: - Try it here

    private var checkCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Try it here")
            TextEditor(text: $sampleText)
                .font(.body)
                .frame(minHeight: 64, maxHeight: 96)
                .padding(8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .focused($fieldFocused)
                .accessibilityIdentifier("setup.testField")
            if let detectedMessage {
                Label(detectedMessage, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.green)
            } else {
                Text("Keyboard: tap the text, hold the globe key and pick Control-V. Translate menu: select the text and tap Translate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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

    private func card<Action: View>(title: String, symbol: String, pill: Pill, steps: [Step], detail: String, @ViewBuilder action: () -> Action) -> some View {
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
            action()
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
        Button("Start translating", action: onDone)
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .background(.bar)
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Live status

    /// Polls while the sheet is on screen. iOS offers no notification for
    /// "the user enabled your keyboard" or "your extension just ran", so a
    /// short poll is the only way to react; it restarts on every scene change
    /// so coming back from Settings refreshes at once.
    private func watchForChanges() async {
        refresh()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            let wasReady = anyReady
            let keyboardWas = keyboard
            let menuWas = menuReady
            refresh()
            if anyReady, !wasReady {
                if keyboard == .ready, keyboardWas != .ready { detectedMessage = "Keyboard detected with Full Access" }
                if menuReady, !menuWas { detectedMessage = "Translate menu detected" }
                fieldFocused = false
                try? await Task.sleep(for: .seconds(1.6))
                onDone()
                return
            }
        }
    }

    private func refresh() {
        keyboard = SetupState.keyboardStatus
        menuReady = SetupState.translationProviderReady
    }
}
