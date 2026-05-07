import ControlVCore
import Foundation

struct HistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let source: String
    let translated: String
    let language: SupportedLanguage
    let tone: Tone
    let timestamp: Date
}

/// Local-only translation history. Persisted to App Group UserDefaults.
/// Capped at 50 most-recent entries.
final class HistoryStore {
    static let shared = HistoryStore()

    private let maxEntries = 50
    private let key = "iOSHistory"

    private var defaults: UserDefaults {
        UserDefaults(suiteName: iOSSettingsStore.appGroup) ?? .standard
    }

    func all() -> [HistoryEntry] {
        guard let data = defaults.data(forKey: key),
              let entries = try? JSONDecoder().decode([HistoryEntry].self, from: data) else {
            return []
        }
        return entries
    }

    func append(
        source: String,
        translated: String,
        language: SupportedLanguage,
        tone: Tone
    ) {
        let entry = HistoryEntry(
            id: UUID(),
            source: source,
            translated: translated,
            language: language,
            tone: tone,
            timestamp: Date()
        )
        var current = all()
        current.insert(entry, at: 0)
        if current.count > maxEntries {
            current = Array(current.prefix(maxEntries))
        }
        save(current)
    }

    func remove(id: UUID) {
        let filtered = all().filter { $0.id != id }
        save(filtered)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }

    private func save(_ entries: [HistoryEntry]) {
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: key)
        }
    }
}
