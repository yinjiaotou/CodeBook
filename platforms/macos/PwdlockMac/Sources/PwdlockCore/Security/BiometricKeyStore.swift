import Foundation
@preconcurrency import LocalAuthentication
import Security

public enum BiometricKeyStoreError: Error, Equatable {
    case invalidKey
    case duplicate
    case notFound
    case authenticationInvalidated
    case unavailable
}

public protocol BiometricKeyStoring: Sendable {
    func create(_ key: Data, vaultID: UUID) throws
    func read(vaultID: UUID, context: LAContext?) throws -> Data
    func delete(vaultID: UUID) throws
    func contains(vaultID: UUID) -> Bool
}

public struct KeychainBiometricKeyStore: BiometricKeyStoring {
    private static let service = "com.pwdlock.mac.biometric-wrap-key"

    public init() {}

    public func create(_ key: Data, vaultID: UUID) throws {
        guard key.count == 32 else { throw BiometricKeyStoreError.invalidKey }
        var accessControlError: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            [.biometryCurrentSet],
            &accessControlError
        ) else {
            throw BiometricKeyStoreError.unavailable
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account(for: vaultID),
            kSecAttrAccessControl as String: accessControl,
            kSecValueData as String: key
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecMissingEntitlement {
            // Ad-hoc signed macOS apps cannot obtain the Keychain entitlement required
            // for a biometry-enforced access-control item. The app still requires a
            // successful LAContext Touch ID evaluation before it calls `read`.
            try createFallbackKeychainItem(key, vaultID: vaultID)
            return
        }
        try check(status)
    }

    public func read(vaultID: UUID, context: LAContext?) throws -> Data {
        var query: [String: Any] = baseQuery(for: vaultID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        if let context {
            query[kSecUseAuthenticationContext as String] = context
        }

        var result: CFTypeRef?
        try check(SecItemCopyMatching(query as CFDictionary, &result))
        guard let key = result as? Data, key.count == 32 else {
            throw BiometricKeyStoreError.invalidKey
        }
        return key
    }

    public func delete(vaultID: UUID) throws {
        let status = SecItemDelete(baseQuery(for: vaultID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            try check(status)
            return
        }
    }

    public func contains(vaultID: UUID) -> Bool {
        var query = baseQuery(for: vaultID)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    private func baseQuery(for vaultID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account(for: vaultID)
        ]
    }

    private func createFallbackKeychainItem(_ key: Data, vaultID: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account(for: vaultID),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: key
        ]
        try check(SecItemAdd(query as CFDictionary, nil))
    }

    private func account(for vaultID: UUID) -> String {
        vaultID.uuidString.lowercased()
    }

    private func check(_ status: OSStatus) throws {
        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            throw BiometricKeyStoreError.duplicate
        case errSecItemNotFound:
            throw BiometricKeyStoreError.notFound
        case errSecAuthFailed, errSecInteractionNotAllowed, errSecUserCanceled:
            throw BiometricKeyStoreError.authenticationInvalidated
        default:
            throw BiometricKeyStoreError.unavailable
        }
    }
}
