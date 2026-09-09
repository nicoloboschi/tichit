import Foundation

/// Append-only log of every rewrite, so the app can later learn which mistakes
/// keep coming back. One JSON object per line.
enum History {
    private static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Tich", isDirectory: true)
    }()

    static var fileURL: URL { directory.appendingPathComponent("history.jsonl") }

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
