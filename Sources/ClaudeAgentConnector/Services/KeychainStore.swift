import Foundation
#if canImport(Security)
import Security
#endif

enum SecretField: String, CaseIterable {
    case appLevelToken
    case botToken
}

protocol SecretsStore {
    func load(field: SecretField) -> String
    func save(value: String, field: SecretField) throws
    func remove(field: SecretField) throws
}

enum KeychainStoreError: Error {
    case unexpectedStatus(Int32)
}

final class KeychainStore: SecretsStore {
    private let service = "com.xiaoshuiz.claude-agent-connector"
    private let fallbackDefaults = UserDefaults.standard

    func load(field: SecretField) -> String {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: field.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            return ""
        }

        guard let data = item as? Data else {
            return ""
        }

        return String(data: data, encoding: .utf8) ?? ""
        #else
        return fallbackDefaults.string(forKey: field.rawValue) ?? ""
        #endif
    }

    func save(value: String, field: SecretField) throws {
        #if canImport(Security)
        let encoded = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: field.rawValue
        ]

        SecItemDelete(query as CFDictionary)

        let payload: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: field.rawValue,
            kSecValueData as String: encoded
        ]

        let status = SecItemAdd(payload as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
        #else
        fallbackDefaults.set(value, forKey: field.rawValue)
        #endif
    }

    func remove(field: SecretField) throws {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: field.rawValue
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
        #else
        fallbackDefaults.removeObject(forKey: field.rawValue)
        #endif
    }
}
