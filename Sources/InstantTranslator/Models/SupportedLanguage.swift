import Foundation

enum SupportedLanguage: String, CaseIterable, Codable, Identifiable {
    case english = "English"
    case spanish = "Spanish"
    case french = "French"
    case german = "German"
    case portuguese = "Portuguese"
    case italian = "Italian"
    case dutch = "Dutch"
    case russian = "Russian"
    case chinese = "Chinese (Simplified)"
    case japanese = "Japanese"
    case korean = "Korean"
    case arabic = "Arabic"

    var id: String { rawValue }

    var bcp47: String {
        switch self {
        case .english: "en"
        case .spanish: "es"
        case .french: "fr"
        case .german: "de"
        case .portuguese: "pt"
        case .italian: "it"
        case .dutch: "nl"
        case .russian: "ru"
        case .chinese: "zh-Hans"
        case .japanese: "ja"
        case .korean: "ko"
        case .arabic: "ar"
        }
    }
}
