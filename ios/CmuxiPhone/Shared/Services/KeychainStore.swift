import Foundation
import Security

/// Minimal Keychain wrapper for secret strings (the per-device bearer tokens
/// that grant terminal/approval control over a paired Mac). Tokens are stored
/// with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` so they never sync to
/// iCloud, never leave the device, and are unreadable while the device is locked
/// — strictly stronger than the old plaintext `UserDefaults` storage.
enum KeychainStore {

    /// Namespacing the items under one service keeps them isolated from any
    /// other generic-password items and easy to enumerate/clear.
    private static let service = "com.cmuxiphone.tokens"

    /// Store (or, with a nil value, delete) a secret for `account`. Returns true on success.
    @discardableResult
    static func set(_ value: String?, for account: String) -> Bool {
        guard let value, let data = value.data(using: .utf8) else {
            return delete(account)
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
        return false
    }

    /// Read a secret for `account`, or nil if absent.
    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    /// Delete the secret for `account`. Returns true if it's gone afterwards.
    @discardableResult
    static func delete(_ account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// One-time migration: if a token still lives in `UserDefaults[key]`, move it
    /// into the Keychain under `account` and scrub the plaintext copy. Returns the
    /// resolved token (Keychain first, then the migrated legacy value, else nil).
    @discardableResult
    static func migrate(fromUserDefaults key: String, account: String) -> String? {
        if let existing = get(account) {
            UserDefaults.standard.removeObject(forKey: key) // drop any stale plaintext copy
            return existing
        }
        if let legacy = UserDefaults.standard.string(forKey: key), !legacy.isEmpty {
            // Only scrub the plaintext copy once the Keychain write is CONFIRMED;
            // a failed write must not lose the token. The app uses the value this
            // session regardless, and retries the migration on the next launch.
            if set(legacy, for: account) {
                UserDefaults.standard.removeObject(forKey: key)
            }
            return legacy
        }
        return nil
    }
}
