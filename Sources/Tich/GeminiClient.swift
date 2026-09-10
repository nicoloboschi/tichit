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

/// One word or expression from the rewrite, explained in Italian.
struct GlossaryItem: Codable, Identifiable {
    let term: String
    let italian: String
    let note: String?

    var id: String { term + italian }
}

struct Suggestion: Codable {
    let improved: String
    let notes: [Note]
    let alternative: String?
    let glossary: [GlossaryItem]?
    /// Set only when the input was Italian: the word-for-word English, for contrast.
    let literal: String?
    /// "en", "it" or "mixed".
    let sourceLanguage: String?

    var wasItalian: Bool { sourceLanguage == "it" }
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
    You are an English writing coach for an Italian speaker. The input may be English,
    Italian, or a mix. Set `sourceLanguage` to "en", "it" or "mixed" accordingly.

    If the input is ENGLISH: rewrite it so it sounds like natural, idiomatic English
    written by a native speaker. Set `literal` to null.

    If the input is ITALIAN: translate it into the English a native speaker would
    actually write in that situation — NOT a word-for-word translation. Then set
    `literal` to the word-for-word English rendering of the Italian, so the learner can
    see the gap between the two, and use `notes` to explain where and why the natural
    version departs from it (false friends, calques, idioms, register, verb patterns).

    Rules:
    - Preserve the author's meaning, intent and level of detail. Never invent facts.
    - Preserve the register unless the requested tone says otherwise.
    - Fix grammar, articles, prepositions, tenses, word order and calques from Italian.
    - `improved` holds the final English only — no preamble, no quotes.
    - `notes`: at most 5 of the most instructive changes. Each has the original
      fragment, the replacement, and a `reason` WRITTEN IN ITALIAN explaining the rule
      so the learner can generalise from it.
    - `glossary`: every word or expression in `improved` that is worth learning —
      idioms, phrasal verbs, collocations, and any word whose sense is not obvious.
      `term` is the English word or expression exactly as it appears in `improved`,
      `italian` is its meaning in Italian IN THIS CONTEXT, and `note` is an optional
      short Italian remark on usage, register or a false friend to avoid. Skip trivial
      function words (the, and, is). Aim for the 3-8 items that actually teach something.
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
            "literal": ["type": "STRING", "nullable": true],
            "sourceLanguage": ["type": "STRING", "enum": ["en", "it", "mixed"]],
            "glossary": [
                "type": "ARRAY",
                "items": [
                    "type": "OBJECT",
                    "properties": [
                        "term": ["type": "STRING"],
                        "italian": ["type": "STRING"],
                        "note": ["type": "STRING", "nullable": true],
                    ],
                    "required": ["term", "italian"],
                ],
            ],
        ],
        "required": ["improved", "notes", "glossary", "sourceLanguage"],
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
