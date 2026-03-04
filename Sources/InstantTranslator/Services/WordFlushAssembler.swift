import Foundation

struct WordFlushAssembler {
    private(set) var committedText = ""
    private var pendingText = ""
    private var lastEmissionAt: Date?
    private let forceFlushInterval: TimeInterval

    init(forceFlushInterval: TimeInterval = 0.12) {
        self.forceFlushInterval = forceFlushInterval
    }

    mutating func append(_ chunk: String, at timestamp: Date = Date()) -> String? {
        guard !chunk.isEmpty else { return nil }
        pendingText += chunk

        if shouldFlushForWordBoundary {
            return flush(at: timestamp)
        }

        if let lastEmissionAt,
           timestamp.timeIntervalSince(lastEmissionAt) >= forceFlushInterval {
            return flush(at: timestamp)
        }

        if lastEmissionAt == nil {
            lastEmissionAt = timestamp
        }
        return nil
    }

    mutating func forceFlush(at timestamp: Date = Date()) -> String? {
        guard !pendingText.isEmpty else { return nil }
        return flush(at: timestamp)
    }

    var fullText: String { committedText + pendingText }

    private var shouldFlushForWordBoundary: Bool {
        guard let last = pendingText.last else { return false }
        return last.isWhitespace
    }

    private mutating func flush(at timestamp: Date) -> String {
        committedText += pendingText
        pendingText = ""
        lastEmissionAt = timestamp
        return committedText
    }
}
