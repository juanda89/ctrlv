import Foundation

enum Tone: String, CaseIterable, Codable, Identifiable {
    case original = "Original"
    case formal = "Formal"
    case casual = "Casual"
    case concise = "Concise"
    case custom = "Custom"

    var id: String { rawValue }
}
