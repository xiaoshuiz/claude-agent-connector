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

final class KeychainStore: SecretsStore {
    private let service = "com.xiaoshuiz.claude-agent-connector"
    private let fallbackDefaults = UserDefaults.standard

    func load(field: SecretField) -> String {
        #if canImport(Security)
        if let value = loadFromKeychain(field: field) {
            return value
        }
        return loadFromFallback(field: field)
        #else
        return loadFromFallback(field: field)
        #endif
    }

    func save(value: String, field: SecretField) throws {
        #if canImport(Security)
        let status = saveToKeychain(value: value, field: field)
        if status == errSecSuccess {
            removeFromFallback(field: field)
            return
        }

        saveToFallback(value: value, field: field)
        logKeychainFallback(operation: "save", field: field, status: status)
        #else
        saveToFallback(value: value, field: field)
        #endif
    }

    func remove(field: SecretField) throws {
        #if canImport(Security)
        let status = SecItemDelete(baseQuery(field: field) as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            removeFromFallback(field: field)
            return
        }

        removeFromFallback(field: field)
        logKeychainFallback(operation: "remove", field: field, status: status)
        #else
        removeFromFallback(field: field)
        #endif
    }

    private func fallbackKey(for field: SecretField) -> String {
        "\(service).fallback.\(field.rawValue)"
    }

    private func loadFromFallback(field: SecretField) -> String {
        fallbackDefaults.string(forKey: fallbackKey(for: field)) ?? ""
    }

    private func saveToFallback(value: String, field: SecretField) {
        fallbackDefaults.set(value, forKey: fallbackKey(for: field))
    }

    private func removeFromFallback(field: SecretField) {
        fallbackDefaults.removeObject(forKey: fallbackKey(for: field))
    }

    #if canImport(Security)
    private func baseQuery(field: SecretField) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: field.rawValue
        ]
    }

    private func loadFromKeychain(field: SecretField) -> String? {
        var query = baseQuery(field: field)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            logKeychainFallback(operation: "load", field: field, status: status)
            return nil
        }

        guard let data = item as? Data else {
            logKeychainFallback(operation: "load", field: field, status: errSecDecode)
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    private func saveToKeychain(value: String, field: SecretField) -> OSStatus {
        let query = baseQuery(field: field)
        let deleteStatus = SecItemDelete(query as CFDictionary)
        if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
            return deleteStatus
        }

        var payload = query
        payload[kSecValueData as String] = Data(value.utf8)
        return SecItemAdd(payload as CFDictionary, nil)
    }

    private func logKeychainFallback(operation: String, field: SecretField, status: OSStatus) {
        NSLog("[KeychainStore] \(operation) failed for \(field.rawValue), status=\(status). Falling back to UserDefaults.")
    }
    #endif
}
