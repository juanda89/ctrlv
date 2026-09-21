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

    /// The system keyboard is 259 pt tall on this phone (51 pt of predictive
    /// bar above 43 pt keys). iOS draws a 16 pt lip above a third-party
    /// keyboard and KeyboardKit's four rows take 216 pt, so 27 pt here makes
    /// the keyboard exactly as tall as the system one: apps do not reflow when
    /// the user switches keyboards, and callouts have room above the top row.
    static let bandHeight: CGFloat = 27

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

    private var calloutStyle: Callouts.CalloutStyle {
        .init(
            backgroundColor: dark ? Color(red: 92/255, green: 92/255, blue: 94/255) : .white,
            borderColor: .clear,
            cornerRadius: 10,
            foregroundColor: dark ? .white : .black,
            inputItemFont: .init(.title, .regular),
            inputItemMinSize: .init(width: 0, height: 44),
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
        .frame(height: 26)
        .glassCard(9)
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
    }
}
