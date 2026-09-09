import Foundation

/// Append-only log of every rewrite, so the app can later learn which mistakes
/// keep coming back. One JSON object per line.
enum History {
    private static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Tich", isDirectory: true)
    }()

    static var fileURL: URL { directory.appendingPathComponent("history.jsonl") }

    struct Entry: Identifiable, Decodable {
        let date: Date
        let tone: String
        let original: String
        let improved: String
        let notes: [Note]

        var id: String { ISO8601DateFormatter().string(from: date) + original }
    }

    /// Newest first. Unparseable lines are skipped rather than failing the whole log.
    static func load() -> [Entry] {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8)
        else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            guard let date = ISO8601DateFormatter().date(from: raw) else {
                throw DecodingError.dataCorruptedError(
                    in: try decoder.singleValueContainer(),
                    debugDescription: "bad date \(raw)"
                )
            }
            return date
        }

        return text
            .split(separator: "\n")
            .compactMap { try? decoder.decode(Entry.self, from: Data($0.utf8)) }
            .reversed()
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    static func append(original: String, suggestion: Suggestion, tone: Tone) {
        let entry: [String: Any] = [
            "date": ISO8601DateFormatter().string(from: Date()),
            "tone": tone.rawValue,
            "original": original,
            "improved": suggestion.improved,
            "notes": suggestion.notes.map {
                ["original": $0.original, "suggestion": $0.suggestion, "reason": $0.reason]
            },
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: entry) else { return }
        var line = data
        line.append(0x0A)

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: fileURL)
        }
    }
}
