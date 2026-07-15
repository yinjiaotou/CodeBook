import Foundation
import LocalAuthentication
import Testing
@testable import PwdlockCore

private let biometricKeyStoreVaultID = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!

@Test("biometric key store contract creates reads detects and deletes one key")
func biometricKeyStoreContract() throws {
    let store = TestBiometricKeyStore()
    let key = Data(repeating: 7, count: 32)

    #expect(!store.contains(vaultID: biometricKeyStoreVaultID))
    try store.create(key, vaultID: biometricKeyStoreVaultID)
    #expect(store.contains(vaultID: biometricKeyStoreVaultID))
    #expect(try store.read(vaultID: biometricKeyStoreVaultID, context: nil) == key)
    try store.delete(vaultID: biometricKeyStoreVaultID)
    #expect(!store.contains(vaultID: biometricKeyStoreVaultID))
    #expect(throws: BiometricKeyStoreError.notFound) {
        _ = try store.read(vaultID: biometricKeyStoreVaultID, context: nil)
    }
}

@Test("system biometric wrappers retain the required Touch ID and Keychain policies")
func systemBiometricWrapperSecurityContract() throws {
    let testFile = URL(filePath: #filePath)
    let packageDirectory = testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let keyStoreSource = try String(
        contentsOf: packageDirectory.appending(path: "Sources/PwdlockCore/Security/BiometricKeyStore.swift"),
        encoding: .utf8
    )
    let authenticatorSource = try String(
        contentsOf: packageDirectory.appending(path: "Sources/PwdlockCore/Application/BiometricAuthenticator.swift"),
        encoding: .utf8
    )

    #expect(keyStoreSource.contains("kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly"))
    #expect(keyStoreSource.contains("kSecAttrAccessibleWhenUnlockedThisDeviceOnly"))
    #expect(keyStoreSource.contains(".biometryCurrentSet"))
    #expect(keyStoreSource.contains("errSecMissingEntitlement"))
    #expect(keyStoreSource.contains("createFallbackKeychainItem"))
    #expect(keyStoreSource.contains("interactionNotAllowed = true"))
    #expect(keyStoreSource.contains("kSecUseAuthenticationContext"))
    #expect(authenticatorSource.contains(".deviceOwnerAuthenticationWithBiometrics"))
    #expect(authenticatorSource.contains("biometryType == .touchID"))
    #expect(authenticatorSource.contains("invalidate()"))
}

private final class TestBiometricKeyStore: BiometricKeyStoring, @unchecked Sendable {
    private var keys: [UUID: Data] = [:]

    func create(_ key: Data, vaultID: UUID) throws {
        guard keys[vaultID] == nil else { throw BiometricKeyStoreError.duplicate }
        keys[vaultID] = key
    }

    func read(vaultID: UUID, context: LAContext?) throws -> Data {
        guard let key = keys[vaultID] else { throw BiometricKeyStoreError.notFound }
        return key
    }

    func delete(vaultID: UUID) throws {
        keys[vaultID] = nil
    }

    func contains(vaultID: UUID) -> Bool {
        keys[vaultID] != nil
    }
}
