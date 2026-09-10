import Foundation

/// Calls the Codex backend directly with the CLI's OAuth login — no API key, and
/// none of the agent-loop overhead of shelling out to `codex exec`.
///
/// Request shape ported from Hindsight's `codex_llm.py`: a single forced function
/// tool whose parameters are the response schema, so the backend does constrained
/// decoding and the answer arrives as tool-call arguments rather than parsed prose.
struct CodexDirectClient: RewriteProvider {
    var model = "gpt-5.6-luna"

    private static let baseURL = "https://chatgpt.com/backend-api"
    private static let originator = "codex_cli_rs"
    private static let userAgent = "codex_cli_rs/0.0.0 (Tich)"
    private static let toolName = "structured_response"

    func improve(text: String, tone: Tone) async throws -> Suggestion {
        let tokens = try await CodexAuth.fresh()
        do {
            return try await send(text: text, tone: tone, tokens: tokens)
        } catch CodexBackendError.unauthorized {
            // Reactive refresh: the server rejected a token we believed was fresh.
            let refreshed = try await CodexAuth.refresh(tokens)
            return try await send(text: text, tone: tone, tokens: refreshed)
        }
    }

    private func send(text: String, tone: Tone, tokens: CodexTokens) async throws -> Suggestion {
        var request = URLRequest(url: URL(string: "\(Self.baseURL)/codex/responses")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(tokens.accountId, forHTTPHeaderField: "OpenAI-Account-ID")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://chatgpt.com", forHTTPHeaderField: "Origin")
        request.setValue(Self.originator, forHTTPHeaderField: "originator")

        let payload: [String: Any] = [
            "model": model,
            "instructions": Prompts.system,
            "input": [
                [
                    "type": "message",
                    "role": "user",
                    "content": "Requested tone: \(tone.instruction)\n\nText:\n\(text)",
                ]
            ],
            "tools": [
                [
                    "type": "function",
                    "name": Self.toolName,
                    "description": "Return the structured response.",
                    "parameters": Self.schema,
                ]
            ],
            "tool_choice": ["type": "function", "name": Self.toolName],
            "parallel_tool_calls": false,
            "reasoning": ["summary": "auto", "effort": "low"],
            "store": false,
            "stream": true,
            "include": ["reasoning.encrypted_content"],
            "prompt_cache_key": UUID().uuidString,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (stream, response) = try await URLSession.shared.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status != 401, status != 403 else {
            throw CodexBackendError.unauthorized
        }
        guard (200..<300).contains(status) else {
            var body = ""
            for try await line in stream.lines where body.count < 500 { body += line }
            throw CodexBackendError.http(status, body)
        }

        guard let arguments = try await Self.parseToolCall(from: stream) else {
            throw CodexBackendError.noStructuredResponse
        }
        return try JSONDecoder().decode(Suggestion.self, from: Data(arguments.utf8))
    }

    /// Reads the SSE stream and returns the forced tool call's arguments.
    private static func parseToolCall(from stream: URLSession.AsyncBytes) async throws -> String? {
        var event = ""
        for try await line in stream.lines {
            if line.hasPrefix("event: ") {
                event = String(line.dropFirst(7))
            } else if line.hasPrefix("data: ") {
                let data = String(line.dropFirst(6))
                if data == "[DONE]" { break }
                guard event == "response.output_item.done",
                      let json = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any],
                      let item = json["item"] as? [String: Any],
                      item["type"] as? String == "function_call",
                      item["name"] as? String == toolName,
                      let arguments = item["arguments"] as? String
                else { continue }
                return arguments
            }
        }
        return nil
    }

    private static var schema: [String: Any] {[
        "type": "object",
        "additionalProperties": false,
        "required": ["improved", "notes", "glossary", "sourceLanguage", "alternative", "literal"],
        "properties": [
            "improved": ["type": "string"],
            "sourceLanguage": ["type": "string", "enum": ["en", "it", "mixed"]],
            "literal": ["type": ["string", "null"]],
            "alternative": ["type": ["string", "null"]],
            "notes": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["original", "suggestion", "reason"],
                    "properties": [
                        "original": ["type": "string"],
                        "suggestion": ["type": "string"],
                        "reason": ["type": "string"],
                    ],
                ],
            ],
            "glossary": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["term", "italian", "note"],
                    "properties": [
                        "term": ["type": "string"],
                        "italian": ["type": "string"],
                        "note": ["type": ["string", "null"]],
                    ],
                ],
            ],
        ],
    ]}
}

enum CodexBackendError: LocalizedError {
    case unauthorized
    case http(Int, String)
    case noStructuredResponse

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Codex rejected the login. Run `codex login` and try again."
        case .http(let code, let body):
            return "Codex backend returned HTTP \(code): \(body)"
        case .noStructuredResponse:
            return "Codex did not return a structured answer."
        }
    }
}
