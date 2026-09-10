import Foundation
import Security

/// Tiny wrapper around a single generic-password keychain item.
enum Keychain {
    private static let service = "dev.tichit.gemini"
    private static let account = "api-key"

    /// Falls back to the pre-rename service so an existing key keeps working.
    private static let legacyService = "dev.tich.gemini"

    static func read() -> String? {
        read(service: service) ?? read(service: legacyService)
    }

    private static func read(service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else { return nil }
        return value
    }

    static func write(_ value: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}

enum Config {
    /// Keychain wins; the env var is the escape hatch for `swift run`.
    static var apiKey: String? {
        Keychain.read() ?? ProcessInfo.processInfo.environment["GEMINI_API_KEY"].flatMap {
            $0.isEmpty ? nil : $0
        }
    }
}
