import AppKit
import Foundation

/// A captured sentence after the model has looked at it.
///
/// The raw capture log stays untouched in `captured.jsonl`; this is a second
/// registry holding the verdict, so a re-review never loses the original.
struct Review: Codable, Identifiable {
    let date: Date
    let app: String
    let original: String
    let improved: String
    let notes: [Note]
    let glossary: [GlossaryItem]?
    let worthReporting: Bool

    var id: String { ISO8601DateFormatter().string(from: date) + original }
}

enum ReviewStore {
    private static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Tichit", isDirectory: true)
    }()

    static var fileURL: URL { directory.appendingPathComponent("reviews.jsonl") }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    static func append(_ review: Review) {
        guard var line = try? encoder.encode(review) else { return }
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

    /// Newest first.
    static func load() -> [Review] {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8)
        else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text
            .split(separator: "\n")
            .compactMap { try? decoder.decode(Review.self, from: Data($0.utf8)) }
            .reversed()
    }

    /// Which sentences have already been through the model.
    static func reviewedTexts() -> Set<String> {
        Set(load().map(\.original))
    }
}

/// Sends captured sentences to the model one at a time and keeps the verdicts.
///
/// Serial by design: a rewrite takes several seconds, and typing arrives in bursts,
/// so a queue keeps this from firing a dozen concurrent requests.
@MainActor
final class ReviewQueue: ObservableObject {
    static let shared = ReviewQueue()

    @Published private(set) var reviews: [Review] = []
    @Published private(set) var pending = 0

    /// Called with a review the model judged worth surfacing.
    var onNotable: ((Review) -> Void)?

    private var queue: [CapturedSentence] = []
    private var isRunning = false
    private var seen: Set<String> = []

    private init() {
        reviews = ReviewStore.load()
        seen = Set(reviews.map(\.original))
    }

    func reload() {
        reviews = ReviewStore.load()
    }

    func enqueue(_ sentence: CapturedSentence) {
        // The same sentence typed twice is the same lesson; review it once.
        guard !seen.contains(sentence.text) else { return }
        seen.insert(sentence.text)
        queue.append(sentence)
        pending = queue.count
        drain()
    }

    /// Picks up anything captured while review was off or the app was closed.
    func enqueueBacklog() {
        for sentence in CaptureStore.load().reversed() {
            enqueue(sentence)
        }
    }

    private func drain() {
        guard !isRunning, !queue.isEmpty else { return }
        isRunning = true

        Task {
            defer {
                isRunning = false
                pending = queue.count
                if !queue.isEmpty { drain() }
            }

            let sentence = queue.removeFirst()
            pending = queue.count

            let client: RewriteProvider = Provider.resolved == .codex
                ? CodexDirectClient()
                : GeminiClient()

            let tone = ReviewSettings.tone
            guard let suggestion = try? await client.improve(text: sentence.text, tone: tone) else {
                return
            }

            // The model sometimes flags a sentence while offering notes that change
            // nothing. A no-op correction is not worth interrupting anyone for.
            let realNotes = suggestion.notes.filter {
                $0.original.trimmingCharacters(in: .whitespacesAndNewlines)
                    != $0.suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let worthReporting = (suggestion.worthReporting ?? false) && !realNotes.isEmpty

            let review = Review(
                date: sentence.date,
                app: sentence.app,
                original: sentence.text,
                improved: suggestion.improved,
                notes: realNotes,
                glossary: suggestion.glossary,
                worthReporting: worthReporting
            )
            ReviewStore.append(review)
            reviews.insert(review, at: 0)

            if review.worthReporting {
                onNotable?(review)
            }
        }
    }
}
