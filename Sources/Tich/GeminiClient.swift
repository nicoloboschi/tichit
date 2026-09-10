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

struct GeminiClient: RewriteProvider {
    var model = "gemini-3.7-flash"

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
                "parts": [["text": Prompts.system]]
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
