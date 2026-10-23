import Foundation
import Security

/// Only this watch can read its session; not synchronized via iCloud Keychain.
enum WatchSecureStore {
    private static let service = "tech.immersion.herpattern.watch.auth"

    static func save(_ data: Data, account: String) throws {
        let key: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        var newItem = key
        newItem[kSecValueData as String] = data
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemUpdate(key as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            let added = SecItemAdd(newItem as CFDictionary, nil)
            guard added == errSecSuccess else { throw WatchAPIError(message: "Cannot save secure session") }
        } else if status != errSecSuccess {
            throw WatchAPIError(message: "Cannot update secure session")
        }
    }

    static func read(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func clear(account: String) {
        let key: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(key as CFDictionary)
    }
}
