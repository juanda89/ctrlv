import ControlVCore
import Foundation

/// The two languages the keyboard translates between without Full Access
/// (on-device models): the target, and the person's own language, or Spanish
/// when the device already reads the target (English for Spanish).
enum OfflineLanguagePair {
    static func partner(of target: SupportedLanguage, preferredLanguages: [String] = Locale.preferredLanguages) -> SupportedLanguage {
        let device = preferredLanguages.first.flatMap { Locale.Language(identifier: $0).languageCode?.identifier }
        let match = SupportedLanguage.allCases.first { Locale.Language(identifier: $0.bcp47).languageCode?.identifier == device }
        if let match, match != target { return match }
        return target == .spanish ? .english : .spanish
    }
}
