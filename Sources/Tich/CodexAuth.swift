import Foundation

/// Codex OAuth credentials, read from the same `auth.json` the Codex CLI writes.
///
/// Ported from Hindsight's `codex_auth.py`: JWT-expiry detection, refresh against
/// the OAuth endpoint, and write-back so the CLI and this app stay in sync.
struct CodexTokens {
    var accessToken: String
    var refreshToken: String?
    var accountId: String
}

enum CodexAuthError: LocalizedError {
    case noAuthFile
    case notLoggedIn
    case refreshExpired(String)
    case refreshFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAuthFile, .notLoggedIn:
            return "Not signed in to Codex. Run `codex login` in a terminal."
        case .refreshExpired(let detail):
            return "Codex login expired: \(detail) Run `codex login` again."
        case .refreshFailed(let detail):
            return "Could not refresh the Codex login: \(detail)"
        }
    }
}

enum CodexAuth {
    // Mirrored from the upstream Codex CLI.
    private static let refreshURL = URL(string: "https://auth.openai.com/oauth/token")!
    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    /// Refresh this far ahead of the `exp` claim so a token cannot expire in flight.
    private static let refreshSkew: TimeInterval = 60

    private static let terminalErrorCodes: Set<String> = [
        "refresh_token_expired", "refresh_token_reused", "refresh_token_invalidated",
    ]

    static var authFile: URL {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"]
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? "\(NSHomeDirectory())/.codex"
        return URL(fileURLWithPath: home).appendingPathComponent("auth.json")
    }

    static var isSignedIn: Bool {
        (try? load()) != nil
    }

    static func load() throws -> CodexTokens {
        guard let data = try? Data(contentsOf: authFile) else { throw CodexAuthError.noAuthFile }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = root["tokens"] as? [String: Any],
              let access = tokens["access_token"] as? String, !access.isEmpty,
              let account = tokens["account_id"] as? String
        else { throw CodexAuthError.notLoggedIn }

        return CodexTokens(
            accessToken: access,
            refreshToken: tokens["refresh_token"] as? String,
            accountId: account
        )
    }

    /// Load, refreshing first when the access token is at or near its expiry.
    static func fresh() async throws -> CodexTokens {
        let tokens = try load()
        guard isStale(tokens.accessToken) else { return tokens }
        return try await refresh(tokens)
    }

    /// The `exp` claim of the JWT, or nil when it cannot be read.
    static func expiry(of jwt: String) -> Date? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)

        guard let data = Data(base64Encoded: base64),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = claims["exp"] as? TimeInterval
        else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    /// An unreadable expiry counts as stale: better one wasted refresh than a 401.
    static func isStale(_ jwt: String) -> Bool {
        guard let expiry = expiry(of: jwt) else { return true }
        return Date().addingTimeInterval(refreshSkew) >= expiry
    }

    @discardableResult
    static func refresh(_ tokens: CodexTokens) async throws -> CodexTokens {
        // The CLI may have refreshed already; adopt its token instead of spending ours.
        if let onDisk = try? load(), onDisk.accessToken != tokens.accessToken, !isStale(onDisk.accessToken) {
            return onDisk
        }
        guard let refreshToken = tokens.refreshToken, !refreshToken.isEmpty else {
            throw CodexAuthError.refreshExpired("no refresh token stored.")
        }

        var request = URLRequest(url: refreshURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

        if status == 401 {
            let code = (body?["error"] as? [String: Any])?["code"] as? String
                ?? body?["error"] as? String ?? "none"
            if terminalErrorCodes.contains(code) {
                throw CodexAuthError.refreshExpired("refresh token is no longer valid (\(code)).")
            }
            throw CodexAuthError.refreshExpired("the server rejected the refresh (\(code)).")
        }
        guard status < 400, let body, let access = body["access_token"] as? String else {
            throw CodexAuthError.refreshFailed("HTTP \(status)")
        }

        var updated = tokens
        updated.accessToken = access
        if let newRefresh = body["refresh_token"] as? String, !newRefresh.isEmpty {
            updated.refreshToken = newRefresh
        }
        persist(updated)
        return updated
    }

    /// Write the new tokens back so the CLI sees them too. Preserves every other
    /// field in the file and replaces it atomically.
    private static func persist(_ tokens: CodexTokens) {
        guard let data = try? Data(contentsOf: authFile),
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var stored = root["tokens"] as? [String: Any]
        else { return }

        stored["access_token"] = tokens.accessToken
        if let refresh = tokens.refreshToken { stored["refresh_token"] = refresh }
        root["tokens"] = stored
        root["last_refresh"] = ISO8601DateFormatter().string(from: Date())

        guard let out = try? JSONSerialization.data(withJSONObject: root, options: .prettyPrinted) else { return }
        let temporary = authFile.deletingLastPathComponent()
            .appendingPathComponent("auth.json.tich-\(UUID().uuidString)")
        do {
            try out.write(to: temporary)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
            _ = try FileManager.default.replaceItemAt(authFile, withItemAt: temporary)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
        }
    }
}
