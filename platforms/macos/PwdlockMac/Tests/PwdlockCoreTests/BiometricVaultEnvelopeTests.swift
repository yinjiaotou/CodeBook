import Foundation
import Testing
@testable import PwdlockCore

private let biometricTestVaultID = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
private let biometricTestVaultKey = Data((0..<32).map(UInt8.init))
private let biometricTestWrappingKey = Data((32..<64).map(UInt8.init))
private let biometricTestNonce = Data(repeating: 0x44, count: 12)

@Test("biometric envelope round trips a vault key in the fixed format")
func biometricEnvelopeRoundTrip() throws {
    let bytes = try BiometricVaultEnvelope.seal(
        vaultKey: biometricTestVaultKey,
        wrappingKey: biometricTestWrappingKey,
        vaultID: biometricTestVaultID,
        nonce: biometricTestNonce
    )

    #expect(bytes.count == 84)
    #expect(
        try BiometricVaultEnvelope.open(
            bytes,
            wrappingKey: biometricTestWrappingKey,
            expectedVaultID: biometricTestVaultID
        ) == biometricTestVaultKey
    )
}

@Test("biometric envelope rejects malformed fixed fields and a different vault")
func biometricEnvelopeRejectsMalformedHeader() throws {
    let original = try sealedBiometricEnvelope()
    for index in [0, 4, 5, 8] {
        var tampered = original
        tampered[index] ^= 0xff
        #expect(throws: BiometricVaultEnvelopeError.invalidEnvelope) {
            _ = try BiometricVaultEnvelope.open(
                tampered,
                wrappingKey: biometricTestWrappingKey,
                expectedVaultID: biometricTestVaultID
            )
        }
    }

    #expect(throws: BiometricVaultEnvelopeError.invalidEnvelope) {
        _ = try BiometricVaultEnvelope.open(
            original,
            wrappingKey: biometricTestWrappingKey,
            expectedVaultID: UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!
        )
    }
}

@Test("biometric envelope authenticates nonce ciphertext tag and wrapping key")
func biometricEnvelopeAuthenticatesEncryptedFields() throws {
    let original = try sealedBiometricEnvelope()
    for index in [24, 36, 68] {
        var tampered = original
        tampered[index] ^= 0xff
        #expect(throws: BiometricVaultEnvelopeError.authenticationFailed) {
            _ = try BiometricVaultEnvelope.open(
                tampered,
                wrappingKey: biometricTestWrappingKey,
                expectedVaultID: biometricTestVaultID
            )
        }
    }

    #expect(throws: BiometricVaultEnvelopeError.authenticationFailed) {
        _ = try BiometricVaultEnvelope.open(
            original,
            wrappingKey: Data(repeating: 0x99, count: 32),
            expectedVaultID: biometricTestVaultID
        )
    }
}

@Test("biometric envelope saves privately and atomically replaces an existing file")
func biometricEnvelopeSavesAtomically() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    let url = directory.appendingPathComponent("vault.biometric", isDirectory: false)
    let first = try sealedBiometricEnvelope()
    let replacement = try BiometricVaultEnvelope.seal(
        vaultKey: biometricTestVaultKey,
        wrappingKey: biometricTestWrappingKey,
        vaultID: biometricTestVaultID,
        nonce: Data(repeating: 0x55, count: 12)
    )

    try BiometricVaultEnvelope.saveAtomically(first, to: url)
    try BiometricVaultEnvelope.saveAtomically(replacement, to: url)

    #expect(try Data(contentsOf: url) == replacement)
    let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
    #expect(permissions?.intValue == 0o600)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["vault.biometric"])
}

private func sealedBiometricEnvelope() throws -> Data {
    try BiometricVaultEnvelope.seal(
        vaultKey: biometricTestVaultKey,
        wrappingKey: biometricTestWrappingKey,
        vaultID: biometricTestVaultID,
        nonce: biometricTestNonce
    )
}
