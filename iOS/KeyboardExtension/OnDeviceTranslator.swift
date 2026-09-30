import ControlVCore
import Foundation
import NaturalLanguage
import Translation

/// The Control-V key without Full Access (App Review 4.4.1: a keyboard must
/// do something useful with and without network access). Apple's on-device
/// models translate between languages the person already downloaded (the
/// app's setup screen or Settings › Apps › Translate); nothing leaves the
/// device. Text already in the target language goes to the other language of
/// the pair (`OfflineLanguagePair`), so the key flips between the two. No
/// tones: those need Control-V's service.
enum OnDeviceTranslator {
    enum Failure: LocalizedError {
        case needsNewerIOS
        case unknownSourceLanguage
        case notDownloaded(SupportedLanguage)
        case unsupportedPair

        var errorDescription: String? {
            switch self {
            case .needsNewerIOS:
                return "Turn on Allow Full Access in Settings to translate."
            case .unknownSourceLanguage:
                return "Couldn't tell which language this is. Type a little more."
            case .notDownloaded(let target):
                return "To translate without Full Access, open Control-V and download \(target.rawValue) and this text's language (once)."
            case .unsupportedPair:
                return "This language pair can't be translated on the device. Turn on Full Access to translate it."
            }
        }
    }

    static func translate(_ text: String, to target: SupportedLanguage) async throws -> String {
        guard #available(iOS 26.0, *) else { throw Failure.needsNewerIOS }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let dominant = recognizer.dominantLanguage, dominant != .undetermined else {
            throw Failure.unknownSourceLanguage
        }
        let source = Locale.Language(identifier: dominant.rawValue)
        var goal = target
        if source.languageCode == Locale.Language(identifier: target.bcp47).languageCode {
            goal = OfflineLanguagePair.partner(of: target)
        }
        let destination = Locale.Language(identifier: goal.bcp47)

        switch await LanguageAvailability().status(from: source, to: destination) {
        case .installed:
            let session = TranslationSession(installedSource: source, target: destination)
            return try await session.translate(text).targetText
        case .supported:
            throw Failure.notDownloaded(goal)
        case .unsupported:
            throw Failure.unsupportedPair
        @unknown default:
            throw Failure.unsupportedPair
        }
    }
}
