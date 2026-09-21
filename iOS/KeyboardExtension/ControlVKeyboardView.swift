import ControlVCore
import KeyboardKit
import SwiftUI

/// KeyboardKit's keyboard dressed as the iOS 26 system keyboard, with the
/// Control-V key and a band above the keys that shows translation status.
///
/// Measured on the system keyboard (iPhone, 402 pt): 43 pt keys, 6 pt between
/// keys, 11 pt between rows, circular 8 pt corners, every key the same white
/// (or the same grey in dark mode), no shadow, 22 pt letters, a blank space
/// bar and a return glyph. KeyboardKit supplies the rest: gestures without
/// dead spots, several fingers at once, callouts, feedback.
struct ControlVKeyboardView: View {
    let services: Keyboard.Services
    let state: Keyboard.State
    @ObservedObject var flow: TranslateFlow
    @ObservedObject private var keyboardContext: KeyboardContext
    @Environment(\.colorScheme) private var scheme

    init(services: Keyboard.Services, state: Keyboard.State, flow: TranslateFlow) {
        self.services = services
        self.state = state
        self._flow = ObservedObject(wrappedValue: flow)
        self._keyboardContext = ObservedObject(wrappedValue: state.keyboardContext)
    }

    /// The band above the keys. It is empty at rest, and it is what gives the
    /// top row's callout room to rise: a keyboard extension is clipped to its
    /// own view, so anything drawn higher is cut off. Apple's own top-row
    /// callout rises 59 pt above the key — it draws outside its keyboard, which
    /// only the system may do. 40 pt here fits our 44 pt callout with the 5.5 pt
    /// row inset, and leaves the keyboard 13 pt taller than the system's.
    static let bandHeight: CGFloat = 40
    /// How far a character callout rises above the key it belongs to.
    static let calloutRise: CGFloat = 44

    var body: some View {
        KeyboardView(
            state: state,
            services: services,
            buttonContent: { params in buttonContent(params.item.action, standard: params.view) },
            buttonView: { $0.view },
            collapsedView: { $0.view },
            emojiKeyboard: { $0.view },
            toolbar: { _ in Keyboard.Toolbar { StatusBand(flow: flow) } }
        )
        .keyboardButtonStyle { params in buttonStyle(params) }
        .keyboardCalloutActions { params in calloutActions(params) }
        .keyboardCalloutStyle(calloutStyle)
        .keyboardToolbarStyle(.init(backgroundColor: .clear, height: Self.bandHeight, minHeight: Self.bandHeight))
        // KeyboardView sizes its toolbar slot from the autocomplete style.
        .autocompleteToolbarStyle(.init(height: Self.bandHeight))
        // The system keyboard keeps 6.5 pt at the sides; KeyboardKit's cells
        // carry 3 pt and it sizes its rows from the full width it is given
        // (its own edge insets only pad, they do not narrow), so give it less.
        .padding(.horizontal, 3.5)
    }

    // MARK: - Content

    @ViewBuilder
    private func buttonContent(_ action: KeyboardAction, standard: Keyboard.ButtonContent) -> some View {
        switch action {
        case .space:
            // Blank, as on the iOS 26 keyboard.
            Color.clear
        case .primary:
            Image(systemName: "return").font(.system(size: 20))
        case ControlVLayoutService.translateAction:
            Text("V").font(.system(size: 23, weight: .heavy, design: .rounded))
        default:
            standard
        }
    }

    // MARK: - Style

    private var dark: Bool { scheme == .dark }
    private var keyFace: Color { dark ? Color(red: 64/255, green: 64/255, blue: 65/255) : .white }
    private var pressedFace: Color { dark ? Color(red: 92/255, green: 92/255, blue: 94/255) : Color(red: 213/255, green: 215/255, blue: 220/255) }

    private func buttonStyle(_ params: Keyboard.ButtonStyleBuilderParams) -> Keyboard.ButtonStyle {
        var style = params.standardStyle(for: keyboardContext)
        style.cornerRadius = 8
        style.shadow = .noShadow
        style.border = .noBorder
        style.foregroundColor = dark ? .white : .black
        switch params.action {
        case ControlVLayoutService.translateAction:
            style.background = .init(backgroundGradient: [Brand.cyan, Brand.blue])
            style.backgroundColor = nil
            style.foregroundColor = .white
        case .character:
            // Letters keep their face while pressed: the callout is the feedback.
            style.backgroundColor = keyFace
            style.nativeFont = .system(size: 22)
        default:
            style.backgroundColor = params.isPressed ? pressedFace : keyFace
        }
        return style
    }

    /// Measured on the iOS 26 keyboard: the balloon is 55 pt wide over a 40 pt
    /// key. Its height is what decides how far it rises, so it is pinned to the
    /// room the band leaves (`calloutRise`), and the curve is narrow enough
    /// that the width stays close to Apple's.
    private var calloutStyle: Callouts.CalloutStyle {
        .init(
            actionItemFont: .init(.title2, .regular),
            actionItemMaxSize: .init(width: 44, height: 44),
            backgroundColor: dark ? Color(red: 92/255, green: 92/255, blue: 94/255) : .white,
            borderColor: .clear,
            cornerRadius: 10,
            curveSize: .init(width: 4, height: 12),
            foregroundColor: dark ? .white : .black,
            inputItemFont: .init(.largeTitle, .regular),
            inputItemMinSize: .init(width: 55, height: Self.calloutRise),
            selectedBackgroundColor: Brand.blue,
            shadowColor: .black.opacity(0.22),
            shadowRadius: 6
        )
    }

    // MARK: - Callouts

    private func calloutActions(_ params: Callouts.ActionsBuilderParams) -> [KeyboardAction]? {
        if case .character(let char) = params.action, let variants = KeyboardLanguage.accents[char.lowercased()] {
            let isUpper = char != char.lowercased()
            return [KeyboardAction](characters: isUpper ? variants.uppercased() : variants)
        }
        return params.standardActions(for: keyboardContext)
    }
}

/// The band above the keys: empty at rest, the translation status while
/// something happens, or the language and tone chips after a long press on V.
struct StatusBand: View {
    @ObservedObject var flow: TranslateFlow

    var body: some View {
        ZStack {
            if flow.isBusy {
                status
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if flow.showsOptions {
                options
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .frame(height: ControlVKeyboardView.bandHeight)
        .animation(.smooth(duration: 0.28), value: flow.phase)
        .animation(.smooth(duration: 0.2), value: flow.showsOptions)
        .tint(Brand.blue)
    }

    @ViewBuilder
    private var status: some View {
        switch flow.phase {
        case .idle:
            EmptyView()
        case .translating:
            strip(symbol: nil, tint: Brand.blue, text: "Translating to \(flow.settings.targetLanguage.rawValue)…") { EmptyView() }
        case .done:
            strip(symbol: "checkmark.circle.fill", tint: .green, text: "Replaced") {
                Button("Undo") { flow.undoReplacement() }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
            }
        case .copiedFallback:
            strip(symbol: "doc.on.clipboard.fill", tint: Brand.blue, text: "Text changed, so it was copied") {
                Button("OK") { flow.dismissStatus() }.font(.caption.weight(.semibold)).buttonStyle(.plain)
            }
        case .error:
            strip(symbol: "exclamationmark.triangle.fill", tint: .orange, text: flow.errorMessage ?? "Something went wrong.") {
                Button("OK") { flow.dismissStatus() }.font(.caption.weight(.semibold)).buttonStyle(.plain)
            }
        }
    }

    private var options: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(SupportedLanguage.allCases) { language in
                    Button(language.rawValue) { flow.select(language: language) }
                }
            } label: {
                chip("globe", flow.settings.targetLanguage.rawValue)
            }
            Menu {
                ForEach(Tone.allCases) { tone in
                    Button(tone.rawValue) { flow.select(tone: tone) }
                }
            } label: {
                chip("slider.horizontal.3", flow.settings.tone.rawValue)
            }
            Spacer(minLength: 0)
            Button { flow.showsOptions = false } label: {
                Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.secondary).padding(6)
            }
            .buttonStyle(.plain)
        }
    }

    private func chip(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.caption.weight(.semibold))
            Text(text).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassPill()
    }

    private func strip<Trailing: View>(symbol: String?, tint: Color, text: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol).font(.footnote).foregroundStyle(tint)
            } else {
                ProgressView().controlSize(.small).tint(tint)
            }
            Text(text).font(.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 32)
        .glassCard(10)
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
    }
}
