import Foundation

enum CodexCLI {
    /// A GUI app inherits a minimal PATH, so look in the usual install locations
    /// rather than relying on `which`.
    static let searchPaths = [
        "\(NSHomeDirectory())/.local/bin/codex",
        "/opt/homebrew/bin/codex",
        "/usr/local/bin/codex",
        "\(NSHomeDirectory())/.bun/bin/codex",
        "\(NSHomeDirectory())/.volta/bin/codex",
    ]

    static var executable: URL? {
        searchPaths
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    /// Signed in means the CLI is installed and has stored credentials.
    static var isAvailable: Bool {
        executable != nil
            && FileManager.default.fileExists(atPath: "\(NSHomeDirectory())/.codex/auth.json")
    }
}

enum CodexError: LocalizedError {
    case notInstalled
    case failed(Int32, String)
    case noOutput(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Codex CLI not found. Install it and run `codex login`, or switch to Gemini in Settings."
        case .failed(let code, let output):
            return "codex exec failed (exit \(code)): \(output)"
        case .noOutput(let output):
            return "Codex returned nothing usable: \(output)"
        }
    }
}

/// Runs the rewrite through the local `codex exec`, which carries the user's
/// existing Codex subscription login — no API key involved.
struct CodexClient: RewriteProvider {
    var model = "gpt-5.6-luna"

    /// Same contract as the Gemini schema, in plain JSON Schema.
    private static let schema = """
    {
      "type": "object",
      "additionalProperties": false,
      "required": ["improved", "notes", "glossary", "sourceLanguage", "alternative", "literal"],
      "properties": {
        "improved": {"type": "string"},
        "sourceLanguage": {"type": "string", "enum": ["en", "it", "mixed"]},
        "literal": {"type": ["string", "null"]},
        "alternative": {"type": ["string", "null"]},
        "notes": {"type": "array", "items": {"type": "object", "additionalProperties": false,
          "required": ["original", "suggestion", "reason"],
          "properties": {"original": {"type": "string"}, "suggestion": {"type": "string"}, "reason": {"type": "string"}}}},
        "glossary": {"type": "array", "items": {"type": "object", "additionalProperties": false,
          "required": ["term", "italian", "note"],
          "properties": {"term": {"type": "string"}, "italian": {"type": "string"}, "note": {"type": ["string", "null"]}}}}
      }
    }
    """

    func improve(text: String, tone: Tone) async throws -> Suggestion {
        guard let executable = CodexCLI.executable else { throw CodexError.notInstalled }

        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("tich-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let schemaURL = scratch.appendingPathComponent("schema.json")
        let outputURL = scratch.appendingPathComponent("out.json")
        try Self.schema.write(to: schemaURL, atomically: true, encoding: .utf8)

        let prompt = """
        \(Prompts.system)

        Answer with the JSON described by the output schema and nothing else. Do not
        read or write any files, do not run any commands, and do not explore the
        filesystem — this is a pure text task.

        Requested tone: \(tone.instruction)

        Text:
        \(text)
        """

        let process = Process()
        process.executableURL = executable
        process.arguments = [
            "exec",
            "--ephemeral",
            "--skip-git-repo-check",
            "--ignore-user-config",
            "--sandbox", "read-only",
            "--color", "never",
            "--model", model,
            "--output-schema", schemaURL.path,
            "--output-last-message", outputURL.path,
            "--cd", scratch.path,
            prompt,
        ]

        // `codex exec` blocks reading stdin when it is not a TTY, so close it.
        process.standardInput = FileHandle.nullDevice
        let logURL = scratch.appendingPathComponent("codex.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: logURL)
        process.standardOutput = log
        process.standardError = log

        try await Self.run(process, logURL: logURL, outputURL: outputURL)
        try? log.close()

        guard let data = try? Data(contentsOf: outputURL), !data.isEmpty else {
            throw CodexError.noOutput("no last message written")
        }
        let raw = String(decoding: data, as: UTF8.self)
        guard let json = Self.extractJSON(from: raw) else {
            throw CodexError.noOutput(raw)
        }
        return try JSONDecoder().decode(Suggestion.self, from: Data(json.utf8))
    }

    private static func run(_ process: Process, logURL: URL, outputURL: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { proc in
                // A non-zero exit still counts if the message file was written.
                let wroteMessage = (try? Data(contentsOf: outputURL)).map { !$0.isEmpty } ?? false
                if proc.terminationStatus != 0, !wroteMessage {
                    let log = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
                    continuation.resume(
                        throwing: CodexError.failed(proc.terminationStatus, String(log.suffix(500)))
                    )
                } else {
                    continuation.resume()
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// The model may wrap the JSON in prose or a fenced block; take the object.
    private static func extractJSON(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") { return trimmed }
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}"),
              start < end
        else { return nil }
        return String(trimmed[start...end])
    }
}
