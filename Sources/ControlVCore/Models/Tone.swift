import Foundation

public enum Tone: String, CaseIterable, Codable, Identifiable, Sendable {
    case original = "Original"
    case formal = "Formal"
    case casual = "Casual"
    case concise = "Concise"
    case custom = "Custom"

    public var id: String { rawValue }
}
