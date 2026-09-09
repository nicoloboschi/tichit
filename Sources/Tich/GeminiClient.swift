import Foundation

enum Tone: String, CaseIterable, Identifiable {
    case neutral = "Neutral"
    case formal = "Formal"
    case friendly = "Friendly"
    case concise = "Concise"

    var id: String { rawValue }

    var instruction: String {
        switch self {
        case .neutral: return "Keep the register neutral and professional."
        case .formal: return "Make it formal and polished, suitable for a business email."
        case .friendly: return "Make it warm and friendly, the way a colleague would write."
        case .concise: return "Make it as short as possible without losing meaning."
        }
    }
}

struct Note: Codable, Identifiable {
    let original: String
    let suggestion: String
    let reason: String

    var id: String { original + suggestion }
}

struct Suggestion: Decodable {
    let improved: String
    let notes: [Note]
    let alternative: String?
}

enum GeminiError: LocalizedError {
    case missingKey
    case http(Int, String)
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "No Gemini API key. Open Settings from the menu bar icon and paste one."
        case .http(let code, let body):
            return "Gemini returned HTTP \(code): \(body)"
        case .badResponse(let detail):
            return "Could not read Gemini's answer: \(detail)"
        }
    }
}

struct GeminiClient {
    var model = "gemini-3.7-flash"

    private static let systemPrompt = """
    You are an English writing coach for a fluent but non-native speaker (Italian first language).
    Rewrite the user's text so it sounds like natural, idiomatic English written by a native speaker.

    Rules:
    - Preserve the author's meaning, intent and level of detail. Never invent facts.
    - Preserve the original language register unless the requested tone says otherwise.
    - Fix grammar, article usage, prepositions, verb tenses, word order and calques from Italian.
    - Prefer the phrasing a native speaker would actually use over a literal correction.
    - If the text is already good, return it unchanged and say so with an empty notes list.
    - Reply with the rewritten text only in `improved` — no preamble, no quotes.
    - In `notes`, list at most 5 of the most instructive changes, each with the original
      fragment, the replacement, and a short reason the learner can generalise from.
    - `alternative` is an optional second phrasing of the whole text, or null.
    """

    private static var schema: [String: Any] {[
        "type": "OBJECT",
        "properties": [
            "improved": ["type": "STRING"],
            "notes": [
                "type": "ARRAY",
                "items": [
                    "type": "OBJECT",
                    "properties": [
                        "original": ["type": "STRING"],
                        "suggestion": ["type": "STRING"],
                        "reason": ["type": "STRING"],
                    ],
                    "required": ["original", "suggestion", "reason"],
                ],
            ],
            "alternative": ["type": "STRING", "nullable": true],
        ],
        "required": ["improved", "notes"],
    ]}

    func improve(text: String, tone: Tone) async throws -> Suggestion {
        guard let key = Config.apiKey else { throw GeminiError.missingKey }

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")

        let body: [String: Any] = [
            "systemInstruction": [
                "parts": [["text": Self.systemPrompt]]
            ],
            "contents": [
                [
                    "role": "user",
                    "parts": [["text": "Requested tone: \(tone.instruction)\n\nText:\n\(text)"]],
                ]
            ],
            "generationConfig": [
                "temperature": 0.3,
                "responseMimeType": "application/json",
                "responseSchema": Self.schema,
                "thinkingConfig": ["thinkingBudget": 0],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GeminiError.badResponse("no HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GeminiError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = root["candidates"] as? [[String: Any]],
            let content = candidates.first?["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]],
            let json = parts.compactMap({ $0["text"] as? String }).first
        else {
            throw GeminiError.badResponse(String(data: data, encoding: .utf8) ?? "empty body")
        }

        do {
            return try JSONDecoder().decode(Suggestion.self, from: Data(json.utf8))
        } catch {
            throw GeminiError.badResponse(json)
        }
    }
}
