import Foundation

enum TrialTranslationService {
    static let dailyLimit = 50
    static let maxCharacters = 3000

    private static let userDefaults = UserDefaults.standard

    static func remainingToday() -> Int {
        max(0, dailyLimit - usedToday())
    }

    static func canTranslate() -> Bool {
        usedToday() < dailyLimit
    }

    static func isTextWithinLimit(_ text: String) -> Bool {
        text.count <= maxCharacters
    }

    static func recordTranslation() {
        let key = todayKey()
        let current = userDefaults.integer(forKey: key)
        userDefaults.set(current + 1, forKey: key)
    }

    static func usedToday() -> Int {
        userDefaults.integer(forKey: todayKey())
    }

    private static func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "trialTranslations_\(formatter.string(from: Date()))"
    }
}
