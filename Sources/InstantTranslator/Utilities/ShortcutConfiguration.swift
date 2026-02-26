import Carbon
import HotKey

struct ShortcutKeyOption: Identifiable, Hashable {
    let letter: String
    let carbonKeyCode: UInt32

    var id: String { letter }
}

enum ShortcutConfiguration {
    static let fixedModifiers: UInt32 = UInt32(cmdKey | shiftKey)
    static let defaultOption: ShortcutKeyOption = option(forLetter: "V")

    static let letterOptions: [ShortcutKeyOption] = {
        let letters = (65...90).compactMap { UnicodeScalar($0).map { String($0) } }
        return letters.compactMap { letter in
            guard let key = Key(string: letter.lowercased()) else { return nil }
            return ShortcutKeyOption(letter: letter, carbonKeyCode: key.carbonKeyCode)
        }
    }()

    static func isValid(keyCode: UInt32) -> Bool {
        letterOptions.contains(where: { $0.carbonKeyCode == keyCode })
    }

    static func option(for keyCode: UInt32) -> ShortcutKeyOption {
        letterOptions.first(where: { $0.carbonKeyCode == keyCode }) ?? defaultOption
    }

    static func option(forLetter letter: String) -> ShortcutKeyOption {
        letterOptions.first(where: { $0.letter == letter.uppercased() }) ??
            ShortcutKeyOption(letter: "V", carbonKeyCode: Key.v.carbonKeyCode)
    }
}
