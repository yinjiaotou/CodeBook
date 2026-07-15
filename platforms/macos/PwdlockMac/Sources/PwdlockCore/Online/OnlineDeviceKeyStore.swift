import CryptoKit
import Foundation
import Security

public enum OnlineDeviceKeyStoreError: Error, Equatable { case unavailable, invalidKey }

/// Stores a device signing private key locally. The raw private key is never sent to sync APIs.
public struct OnlineDeviceKeyStore: Sendable {
    private static let service = "com.pwdlock.mac.online-device-signing-key"
    public init() {}

    public func save(_ key: Curve25519.Signing.PrivateKey, accountID: String) throws {
        delete(accountID: accountID)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: accountID,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: key.rawRepresentation
        ]
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw OnlineDeviceKeyStoreError.unavailable }
    }

    public func read(accountID: String) throws -> Curve25519.Signing.PrivateKey? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service,
                                    kSecAttrAccount as String: accountID, kSecReturnData as String: true,
                                    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw OnlineDeviceKeyStoreError.unavailable }
        do { return try Curve25519.Signing.PrivateKey(rawRepresentation: data) }
        catch { throw OnlineDeviceKeyStoreError.invalidKey }
    }

    public func delete(accountID: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service, kSecAttrAccount as String: accountID] as CFDictionary)
    }
}
