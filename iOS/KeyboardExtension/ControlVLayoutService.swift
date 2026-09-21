import Foundation
import KeyboardKit
import SwiftUI

/// KeyboardKit's iPhone layout with two changes: the middle row carries Ñ
/// when the phone speaks Spanish, and the Control-V key sits between space
/// and return, sized like the other bottom-row system keys.
final class ControlVLayoutService: KeyboardLayout.iPhoneLayoutService {
    static let translateAction = KeyboardAction.custom(named: "Translate and replace")

    init(language: KeyboardLanguage) {
        super.init(
            alphabeticInputSet: language == .spanish ? .spanish : .qwerty,
            numericInputSet: .numeric(currency: "$"),
            symbolicInputSet: .symbolic(currencies: ["€", "£", "¥"])
        )
    }

    /// Measured on the iOS 26 keyboard: 43 pt keys with 6 pt between them
    /// and 11 pt between rows, so a 54 pt row with 3/5.5 pt insets.
    static let rowHeight: CGFloat = 54
    static let insets = EdgeInsets(top: 5.5, leading: 3, bottom: 5.5, trailing: 3)

    override func itemSizeHeight(for action: KeyboardAction, row: Int, index: Int, context: KeyboardContext) -> CGFloat {
        Self.rowHeight
    }

    override func itemInsets(for action: KeyboardAction, row: Int, index: Int, context: KeyboardContext) -> EdgeInsets {
        switch action {
        case .characterMargin, .none: return .init(top: 0, leading: 0, bottom: 0, trailing: 0)
        default: return Self.insets
        }
    }

    override func keyboardLayout(for context: KeyboardContext) -> KeyboardLayout {
        var layout = super.keyboardLayout(for: context)
        layout.deviceConfiguration = .init(buttonCornerRadius: 8, buttonInsets: Self.insets, rowHeight: Self.rowHeight)
        guard let rowIndex = layout.itemRows.indices.last,
              let space = layout.itemRows[rowIndex].first(where: { $0.action == .space }) else { return layout }
        var key = space
        key.action = Self.translateAction
        key.size.width = bottomSystemButtonWidth(for: context)
        layout.itemRows.insert(key, after: .space, inRow: rowIndex)
        return layout
    }
}

extension KeyboardLayout.InputSet {
    /// QWERTY with Ñ after L, as on Apple's Spanish keyboards.
    static var spanish: Self {
        .init(rows: [
            .init(chars: "qwertyuiop"),
            .init(chars: "asdfghjklñ"),
            .init(chars: "zxcvbnm", deviceVariations: [.pad: "zxcvbnm,."]),
        ])
    }
}

/// The letter layout the phone's language expects.
enum KeyboardLanguage {
    case english, spanish

    static var current: KeyboardLanguage {
        let code = Locale.preferredLanguages.first?.prefix(2).lowercased() ?? "en"
        return code == "es" ? .spanish : .english
    }

    /// Long-press variants, Spanish ones first. KeyboardKit's own callouts
    /// cover English; these replace them for the letters that matter here.
    static let accents: [String: String] = [
        "a": "áàäâãåæ",
        "e": "éèëê",
        "i": "íìïî",
        "o": "óòöôõøœ",
        "u": "úüùû",
        "n": "ñ",
        "c": "çćč",
        "s": "ßśš",
        "y": "ÿ",
        "z": "žźż",
        "l": "ł",
    ]
}
