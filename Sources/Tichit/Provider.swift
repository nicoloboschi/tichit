import Foundation

/// Where rewrites come from. Codex uses the local Codex CLI and its existing
/// subscription login; Gemini uses a personal API key.
enum Provider: String, CaseIterable, Identifiable {
    case auto
    case codex
    case gemini

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Automatic"
        case .codex: return "Codex subscription"
        case .gemini: return "Gemini API key"
        }
    }

    /// Prefer Codex when it is signed in: no key to manage, nothing to pay per call.
    static var resolved: Provider {
        switch current {
        case .auto: return CodexAuth.isSignedIn ? .codex : .gemini
        case let explicit: return explicit
        }
    }

    static var current: Provider {
        get {
            UserDefaults.standard.string(forKey: "provider").flatMap(Provider.init(rawValue:)) ?? .auto
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "provider")
        }
    }
}

/// Tone used when reviewing captured sentences. Separate from the composer's picker:
/// what you dash off in Slack should not be judged against a business-email standard.
enum ReviewSettings {
    static var tone: Tone {
        get {
            UserDefaults.standard.string(forKey: "captureTone").flatMap(Tone.init(rawValue:))
                ?? .asWritten
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "captureTone")
        }
    }
}

protocol RewriteProvider {
    func improve(text: String, tone: Tone) async throws -> Suggestion
}
