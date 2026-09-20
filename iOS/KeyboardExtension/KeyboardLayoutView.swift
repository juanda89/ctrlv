import ControlVCore
import SwiftUI
import UIKit

/// A standard QWERTY keyboard drawn to match the system one.
///
/// iOS has no way to add a button to Apple's keyboard, so the only way to put
/// "Translate" one tap away is to ship a full keyboard the user can leave
/// enabled all the time. Everything here exists so that switching to Control-V
/// costs the user nothing: same layout, same key sizes, same planes.
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
    @State private var deleteRepeat: Timer?

    enum Plane { case letters, numbers, symbols }
    enum Shift { case off, on, locked }

    private let rowSpacing: CGFloat = 11
    private let keySpacing: CGFloat = 6
    private let sidePadding: CGFloat = 3
    private let keyHeight: CGFloat = 44

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
        .frame(height: keyHeight * 4 + rowSpacing * 3)
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
            ForEach(keys, id: \.self) { k in
                characterKey(k, width: unit)
            }
        }
    }

    /// Nine letters inset by half a key, the way the system keyboard stages it.
    /// A ten-letter row (Spanish, with Ñ) is flush like the row above it.
    private func middleRow(unit: CGFloat) -> some View {
        let inset = plane == .letters && middleKeys.count < 10
        return HStack(spacing: keySpacing) {
            if inset { Spacer(minLength: 0).frame(width: (unit + keySpacing) / 2) }
            ForEach(middleKeys, id: \.self) { k in
                characterKey(k, width: unit)
            }
            if inset { Spacer(minLength: 0).frame(width: (unit + keySpacing) / 2) }
        }
    }

    private func thirdRow(unit: CGFloat, available: CGFloat) -> some View {
        let keys = thirdKeys
        // The modifier keys absorb whatever the character keys leave over, so
        // the row always ends flush with the ones above it.
        let modifierWidth = floorToPixel((available - CGFloat(keys.count) * unit - CGFloat(keys.count + 1) * keySpacing) / 2)
        return HStack(spacing: keySpacing) {
            switch plane {
            case .letters:
                modifierKey(shiftSymbol, width: modifierWidth, muted: shift == .off) { toggleShift() }
                    .simultaneousGesture(LongPressGesture().onEnded { _ in shift = .locked })
            case .numbers:
                modifierKey(text: "#+=", width: modifierWidth) { plane = .symbols }
            case .symbols:
                modifierKey(text: "123", width: modifierWidth) { plane = .numbers }
            }
            ForEach(keys, id: \.self) { k in
                characterKey(k, width: unit)
            }
            deleteKey(width: modifierWidth)
        }
    }

    private func bottomRow(unit: CGFloat, available: CGFloat) -> some View {
        let sideWidth = floorToPixel(unit * 1.25)
        let returnWidth = floorToPixel(unit * 1.9)
        return HStack(spacing: keySpacing) {
            modifierKey(text: plane == .letters ? "123" : "ABC", width: sideWidth) {
                plane = plane == .letters ? .numbers : .letters
                syncShiftWithContext()
            }
            if actions.showsKeyboardSwitch {
                modifierKey("globe", width: sideWidth) { actions.switchKeyboard() }
            }
            Button { insert(" ") } label: {
                keyFace(Text("space").font(.system(size: 16)), prominent: false)
            }
            .buttonStyle(.plain)
            translateKey(width: sideWidth)
            modifierKey(text: "return", width: returnWidth) { insert("\n") }
        }
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
            keyFace(
                Text("V").font(.system(size: 23, weight: .heavy, design: .rounded)),
                prominent: true,
                brand: true
            )
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

    // MARK: - Keys

    private func characterKey(_ key: String, width: CGFloat) -> some View {
        let label = plane == .letters && shift != .off ? key.uppercased() : key
        return Button { insert(label) } label: {
            keyFace(Text(label).font(.system(size: plane == .letters ? 25 : 22)), prominent: false)
        }
        .buttonStyle(.plain)
        .frame(width: width)
    }

    private func modifierKey(_ symbol: String, width: CGFloat, muted: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            keyFace(Image(systemName: symbol).font(.system(size: 20)), prominent: false, muted: muted)
        }
        .buttonStyle(.plain)
        .frame(width: width)
    }

    private func modifierKey(text: String, width: CGFloat, muted: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            keyFace(Text(text).font(.system(size: 16)), prominent: false, muted: muted)
        }
        .buttonStyle(.plain)
        .frame(width: width)
    }

    private func deleteKey(width: CGFloat) -> some View {
        keyFace(Image(systemName: "delete.left").font(.system(size: 20)), prominent: false, muted: true)
            .frame(width: width)
            .contentShape(Rectangle())
            .onTapGesture { actions.deleteBackward(); syncShiftWithContext() }
            .onLongPressGesture(minimumDuration: 0.35, pressing: { pressing in
                if !pressing { stopDeleteRepeat() }
            }, perform: startDeleteRepeat)
    }

    private func keyFace<Content: View>(_ label: Content, prominent: Bool, muted: Bool = false, brand: Bool = false) -> some View {
        label
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .frame(maxWidth: .infinity)
            .frame(height: keyHeight)
            .background {
                let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
                if brand { shape.fill(Brand.gradient) } else { shape.fill(keyColor(prominent: prominent, muted: muted)) }
            }
            .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.28), radius: 0, y: 1)
    }

    private func keyColor(prominent: Bool, muted: Bool) -> Color {
        if prominent { return Brand.blue }
        if scheme == .dark { return muted ? Color(white: 0.22) : Color(white: 0.29) }
        return muted ? Color(red: 0.67, green: 0.69, blue: 0.72) : .white
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
        actions.insertText(text)
        if plane == .letters, shift == .on { shift = .off }
        if text == "\n" || text == " " { syncShiftWithContext() }
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

    private func startDeleteRepeat() {
        stopDeleteRepeat()
        deleteRepeat = Timer.scheduledTimer(withTimeInterval: 0.09, repeats: true) { _ in
            MainActor.assumeIsolated { actions.deleteBackward() }
        }
    }

    private func stopDeleteRepeat() {
        deleteRepeat?.invalidate()
        deleteRepeat = nil
        syncShiftWithContext()
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
}
