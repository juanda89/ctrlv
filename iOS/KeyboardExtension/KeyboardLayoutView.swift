import ControlVCore
import SwiftUI
import UIKit

/// A QWERTY keyboard drawn to the measurements of the iOS 26 system keyboard
/// (iPhone, 402 pt wide): 43 pt keys, 6 pt between keys, 11 pt between rows,
/// 6.5 pt at the sides, circular 8 pt corners, no shadow, every key the same
/// colour, 24 pt letters, a blank space bar and a return glyph. The only
/// addition is the Control-V key between space and return.
///
/// iOS has no way to add a button to Apple's keyboard, so the only way to put
/// "Translate" one tap away is to ship a full keyboard the user can leave
/// enabled all the time. Everything here exists so that switching to Control-V
/// costs the user nothing.
struct KeyboardLayoutView: View {
    let actions: KeyboardActions
    @Binding var settings: ExtensionSettings
    /// Tapping the Control-V key; a long press opens language and tone instead.
    let onTranslate: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var plane: Plane = .letters
    /// Follows the language the phone is set to, so a Spanish keyboard has its
    /// Ñ where the user expects it instead of an English-only layout.
    var language: KeyboardLanguage = .current
    @State private var shift: Shift = .on
    @State private var lastSpaceAt: Date?

    enum Plane { case letters, numbers, symbols }
    enum Shift { case off, on, locked }

    private let rowSpacing: CGFloat = 11
    private let keySpacing: CGFloat = 6
    private let sidePadding: CGFloat = 6.5
    private let keyHeight: CGFloat = 43
    /// Four rows and three gaps; the controller sizes the input view from it.
    static let height: CGFloat = 43 * 4 + 11 * 3

    private var style: KeyStyle { .system(dark: scheme == .dark, accent: Brand.blue) }

    var body: some View {
        GeometryReader { geo in
            // Widths are floored to a whole device pixel: rounding ten
            // fractional keys up overflows the row and clips the last key.
            let unit = floorToPixel((geo.size.width - keySpacing * 9) / 10)
            VStack(spacing: rowSpacing) {
                letterRow(topRow, unit: unit)
                middleRow(unit: unit)
                thirdRow(unit: unit, available: geo.size.width)
                bottomRow(unit: unit, available: geo.size.width)
            }
            .frame(width: geo.size.width, alignment: .center)
        }
        .padding(.horizontal, sidePadding)
        .frame(height: Self.height)
        .onAppear(perform: syncShiftWithContext)
    }

    private func floorToPixel(_ value: CGFloat) -> CGFloat {
        let scale = max(UIScreen.main.scale, 1)
        return (value * scale).rounded(.down) / scale
    }

    // MARK: - Rows

    private var topRow: [String] {
        switch plane {
        case .letters: return "qwertyuiop".map(String.init)
        case .numbers: return "1234567890".map(String.init)
        case .symbols: return ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="]
        }
    }

    private var middleKeys: [String] {
        switch plane {
        case .letters: return language.middleLetters
        case .numbers: return ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""]
        case .symbols: return ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "·"]
        }
    }

    private var thirdKeys: [String] {
        switch plane {
        case .letters: return "zxcvbnm".map(String.init)
        case .numbers, .symbols: return [".", ",", "?", "!", "'"]
        }
    }

    private func letterRow(_ keys: [String], unit: CGFloat) -> some View {
        HStack(spacing: keySpacing) {
            ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                characterKey(key, width: unit, edge: edge(index, of: keys.count))
            }
        }
    }

    /// Nine letters inset by half a key, the way the system keyboard stages it.
    /// A ten-letter row (Spanish, with Ñ) is flush like the row above it.
    private func middleRow(unit: CGFloat) -> some View {
        let keys = middleKeys
        let inset = plane == .letters && keys.count < 10
        return HStack(spacing: keySpacing) {
            if inset { Spacer(minLength: 0).frame(width: (unit + keySpacing) / 2) }
            ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                characterKey(key, width: unit, edge: edge(index, of: keys.count))
            }
            if inset { Spacer(minLength: 0).frame(width: (unit + keySpacing) / 2) }
        }
    }

    /// Shift and delete are wider and sit a little apart from the letters;
    /// the spacers reproduce that gap whatever the row's width.
    private func thirdRow(unit: CGFloat, available: CGFloat) -> some View {
        let keys = thirdKeys
        let wide = floorToPixel(unit * 1.36)
        let punctuation = floorToPixel((available - 2 * wide - 6 * keySpacing) / 5)
        return HStack(spacing: keySpacing) {
            switch plane {
            case .letters: shiftKey(width: wide)
            case .numbers: modifierKey(text: "#+=", width: wide) { plane = .symbols }
            case .symbols: modifierKey(text: "123", width: wide) { plane = .numbers }
            }
            Spacer(minLength: 0)
            HStack(spacing: keySpacing) {
                ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                    characterKey(key, width: plane == .letters ? unit : punctuation, edge: .none)
                }
            }
            Spacer(minLength: 0)
            deleteKey(width: wide)
        }
        .frame(width: available)
    }

    private func bottomRow(unit: CGFloat, available: CGFloat) -> some View {
        let side = floorToPixel(unit * 1.3)
        let returnWidth = side * 2 + keySpacing
        let space = available - side * 2 - returnWidth - keySpacing * 3
        return HStack(spacing: keySpacing) {
            modifierKey(text: plane == .letters ? "123" : "ABC", width: side) {
                plane = plane == .letters ? .numbers : .letters
                syncShiftWithContext()
            }
            ModifierKeyView(width: space, height: keyHeight, style: style, action: { insert(" ") }) {
                // Blank, as on the iOS 26 keyboard.
                Color.clear
            }
            .accessibilityLabel("space")
            translateKey(width: side)
            ModifierKeyView(width: returnWidth, height: keyHeight, style: style, action: { insert("\n") }) {
                Image(systemName: "return").font(.system(size: 20))
            }
            .accessibilityLabel("return")
        }
    }

    private func edge(_ index: Int, of count: Int) -> KeyView.Edge {
        if index == 0 { return .leading }
        if index == count - 1 { return .trailing }
        return .none
    }

    // MARK: - Keys

    private func characterKey(_ key: String, width: CGFloat, edge: KeyView.Edge) -> some View {
        let uppercase = plane == .letters && shift != .off
        let label = uppercase ? key.uppercased() : key
        let alternatives = plane == .letters ? (KeyboardLanguage.accents[key] ?? []) : []
        return KeyView(
            label: label,
            alternatives: uppercase ? alternatives.map { $0.uppercased() } : alternatives,
            width: width,
            height: keyHeight,
            style: style,
            edge: edge,
            onCommit: { insert($0) }
        )
    }

    private func modifierKey(text: String, width: CGFloat, action: @escaping () -> Void) -> some View {
        ModifierKeyView(width: width, height: keyHeight, style: style, action: action) {
            Text(text).font(.system(size: 17))
        }
        .accessibilityLabel(text)
    }

    private func shiftKey(width: CGFloat) -> some View {
        ModifierKeyView(width: width, height: keyHeight, style: style, action: toggleShift) {
            Image(systemName: shiftSymbol).font(.system(size: 20))
        }
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in shift = .locked })
        .accessibilityLabel("shift")
    }

    private func deleteKey(width: CGFloat) -> some View {
        ModifierKeyView(width: width, height: keyHeight, style: style, repeatWhileHeld: true, action: {
            actions.deleteBackward()
            syncShiftWithContext()
        }) {
            Image(systemName: "delete.left").font(.system(size: 20))
        }
        .accessibilityLabel("delete")
    }

    /// The whole point of the keyboard: translate without leaving it. Sits
    /// where the user's thumb already is, next to space and return.
    private func translateKey(width: CGFloat) -> some View {
        Menu {
            Picker("Language", selection: languageBinding) {
                ForEach(SupportedLanguage.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("Tone", selection: toneBinding) {
                ForEach(Tone.allCases) { Text($0.rawValue).tag($0) }
            }
        } label: {
            Text("V")
                .font(.system(size: 23, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: width, height: keyHeight)
                .background(RoundedRectangle(cornerRadius: style.radius, style: .circular).fill(Brand.gradient))
        } primaryAction: {
            onTranslate()
        }
        .frame(width: width)
        .accessibilityLabel("Translate and replace")
    }

    private var languageBinding: Binding<SupportedLanguage> {
        Binding(get: { settings.targetLanguage }, set: { settings.targetLanguage = $0; ExtensionBridge.save(settings) })
    }

    private var toneBinding: Binding<Tone> {
        Binding(get: { settings.tone }, set: { settings.tone = $0; ExtensionBridge.save(settings) })
    }

    private var shiftSymbol: String {
        switch shift {
        case .off: return "shift"
        case .on: return "shift.fill"
        case .locked: return "capslock.fill"
        }
    }

    // MARK: - Behaviour

    private func insert(_ text: String) {
        if text == " ", isDoubleSpace() {
            // Two quick spaces after a word end the sentence, as on the system keyboard.
            actions.deleteBackward()
            actions.insertText(". ")
            lastSpaceAt = nil
            syncShiftWithContext()
            return
        }
        lastSpaceAt = text == " " ? Date() : nil
        actions.insertText(text)
        if plane == .letters, shift == .on { shift = .off }
        if text == "\n" || text == " " { syncShiftWithContext() }
    }

    private func isDoubleSpace() -> Bool {
        guard let lastSpaceAt, Date().timeIntervalSince(lastSpaceAt) < 0.45,
              let context = actions.contextBeforeInput(), context.hasSuffix(" "),
              let beforeSpace = context.dropLast().last else { return false }
        return beforeSpace.isLetter || beforeSpace.isNumber
    }

    private func toggleShift() {
        shift = shift == .off ? .on : .off
    }

    /// Capitalise at the start of the document and after sentence punctuation,
    /// which is what people expect from the system keyboard.
    private func syncShiftWithContext() {
        guard shift != .locked else { return }
        let context = actions.contextBeforeInput() ?? ""
        let trimmed = context.trimmingCharacters(in: .whitespaces)
        let startsSentence = trimmed.isEmpty || trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?") || context.hasSuffix("\n")
        shift = startsSentence ? .on : .off
    }
}

/// The letter layout the phone's language expects. Only the middle row differs
/// between the layouts Control-V ships; everything else is shared.
enum KeyboardLanguage {
    case english, spanish

    static var current: KeyboardLanguage {
        let code = Locale.preferredLanguages.first?.prefix(2).lowercased() ?? "en"
        return code == "es" ? .spanish : .english
    }

    var middleLetters: [String] {
        switch self {
        case .english: return "asdfghjkl".map(String.init)
        case .spanish: return "asdfghjklñ".map(String.init)
        }
    }

    /// Long-press variants, Spanish ones first.
    static let accents: [String: [String]] = [
        "a": ["á", "à", "ä", "â", "ã", "å", "æ"],
        "e": ["é", "è", "ë", "ê"],
        "i": ["í", "ì", "ï", "î"],
        "o": ["ó", "ò", "ö", "ô", "õ", "ø", "œ"],
        "u": ["ú", "ü", "ù", "û"],
        "n": ["ñ"],
        "c": ["ç", "ć", "č"],
        "s": ["ß", "ś", "š"],
        "y": ["ÿ"],
        "z": ["ž", "ź", "ż"],
        "l": ["ł"],
    ]
}
