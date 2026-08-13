import Foundation
import Security

/// Keychain storage for the API key.
///
/// `UserDefaults` would be the easy place to put this and the wrong one: it is plain text in
/// the app container and it rides along in every backup. The item is marked
/// `WhenUnlockedThisDeviceOnly`, so it is unreadable while the phone is locked and never
/// migrates to another device through iCloud or an encrypted backup.
struct KeychainStore {
    var service: String = "com.ullage.Ullage"

    enum Key: String {
        case openAIAPIKey = "openai-api-key"
    }

    enum KeychainError: LocalizedError {
        case unexpectedStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case let .unexpectedStatus(status):
                let message = SecCopyErrorMessageString(status, nil) as String?
                return message ?? "The keychain returned error \(status)."
            }
        }
    }

    func string(for key: Key) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Writes a value, replacing any existing one. Passing nil removes the item.
    func set(_ value: String?, for key: Key) throws {
        guard let value, !value.isEmpty else {
            try remove(key)
            return
        }
        let data = Data(value.utf8)
        let query = baseQuery(for: key)

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var insert = query
            insert.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        default:
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    func remove(_ key: Key) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func baseQuery(for key: Key) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
    }
}
