import NaturalLanguage
import UIKit

/// What the Control-V key does without Full Access (App Review 4.4.1: a
/// keyboard must stay useful without it): fixes typos with iOS's own spell
/// checker, on the device. `UITextChecker` works in a keyboard without Full
/// Access (it is what local autocomplete uses); Apple's Translation framework
/// does not (its calls never return there), and our service needs the network.
enum OfflineSpelling {
    struct Result: Equatable {
        let text: String
        let fixes: Int
    }

    /// `preferred` are language codes to try besides the detected one (the
    /// device's language, the translation target). Among the checkers that
    /// can actually check, the one with the fewest misspellings wins, which
    /// copes with short texts that language detection cannot place.
    static func correct(_ text: String, preferred: [String]) -> Result {
        let checker = UITextChecker()
        let languages = candidateLanguages(for: text, preferred: preferred, available: UITextChecker.availableLanguages)
            .filter { canCheck($0, checker: checker) }
        guard let language = languages.min(by: { misspelledRanges(in: text, language: $0, checker: checker).count
                                                    < misspelledRanges(in: text, language: $1, checker: checker).count })
        else { return Result(text: text, fixes: 0) }
        return corrections(in: text, language: language, checker: checker)
    }

    /// A listed language whose dictionary is missing reports no misspellings
    /// at all, which would win every comparison: it must flag gibberish.
    static func canCheck(_ language: String, checker: UITextChecker) -> Bool {
        let probe = "qzxwvkj"
        let range = checker.rangeOfMisspelledWord(in: probe, range: NSRange(location: 0, length: (probe as NSString).length),
                                                  startingAt: 0, wrap: false, language: language)
        return range.location != NSNotFound
    }

    // MARK: - Pieces

    static func candidateLanguages(for text: String, preferred: [String], available: [String]) -> [String] {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        // Only the best guess: the runner-up is noise on short texts.
        let detected = recognizer.dominantLanguage.map { [$0.rawValue] } ?? []
        var result: [String] = []
        for code in detected + preferred {
            guard let match = checkerLanguage(for: code, available: available), !result.contains(match) else { continue }
            result.append(match)
        }
        return result
    }

    /// "es" → "es_ES" (or the device region's variant when it exists).
    static func checkerLanguage(for code: String, available: [String]) -> String? {
        let base = String(code.prefix { $0 != "-" && $0 != "_" }).lowercased()
        guard !base.isEmpty else { return nil }
        if let region = Locale.current.region?.identifier, available.contains("\(base)_\(region)") {
            return "\(base)_\(region)"
        }
        return available.first { $0.lowercased() == base || $0.lowercased().hasPrefix(base + "_") }
    }

    static func misspelledRanges(in text: String, language: String, checker: UITextChecker) -> [NSRange] {
        let length = (text as NSString).length
        var ranges: [NSRange] = []
        var start = 0
        while start < length {
            let range = checker.rangeOfMisspelledWord(in: text, range: NSRange(location: 0, length: length),
                                                      startingAt: start, wrap: false, language: language)
            guard range.location != NSNotFound, range.length > 0 else { break }
            ranges.append(range)
            start = range.location + range.length
        }
        return ranges
    }

    private static func corrections(in text: String, language: String, checker: UITextChecker) -> Result {
        let source = text as NSString
        let output = NSMutableString(string: text)
        var fixes = 0
        for range in misspelledRanges(in: text, language: language, checker: checker).reversed() {
            let word = source.substring(with: range)
            guard shouldCorrect(word, at: range.location, in: source),
                  let guess = checker.guesses(forWordRange: range, in: text, language: language)?.first,
                  guess != word else { continue }
            output.replaceCharacters(in: range, with: matchingCase(of: word, guess))
            fixes += 1
        }
        return Result(text: output as String, fixes: fixes)
    }

    /// Leaves alone what a spell checker gets wrong: numbers, handles, links,
    /// single letters, and capitalized words mid-sentence (usually names).
    static func shouldCorrect(_ word: String, at location: Int, in text: NSString) -> Bool {
        guard word.count > 1, word.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789@/_#")) == nil else { return false }
        guard let first = word.first, first.isUppercase, word.lowercased() != word else { return true }
        return isSentenceStart(location, in: text)
    }

    private static func isSentenceStart(_ location: Int, in text: NSString) -> Bool {
        var index = location - 1
        while index >= 0 {
            let character = text.character(at: index)
            guard let scalar = Unicode.Scalar(character) else { return false }
            if CharacterSet.whitespaces.contains(scalar) { index -= 1; continue }
            return ".!?¿¡\n".unicodeScalars.contains(scalar)
        }
        return true
    }

    static func matchingCase(of original: String, _ guess: String) -> String {
        if original.count > 1, original == original.uppercased() { return guess.uppercased() }
        if let first = original.first, first.isUppercase { return guess.prefix(1).uppercased() + guess.dropFirst() }
        return guess
    }
}
