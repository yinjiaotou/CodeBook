import Foundation
import Testing
@testable import PwdlockCore

@Test("master password envelope round-trips a random vault key")
func wrapsAndUnwrapsVaultKey() throws {
    let vaultKey = Data(0..<32)
    let metadata = try VaultKeyEnvelope.wrap(
        vaultKey: vaultKey,
        masterPassword: "correct horse battery staple",
        vaultID: Data(repeating: 0x11, count: 16),
        passwordSalt: Data(repeating: 0x22, count: 16),
        wrapNonce: Data(repeating: 0x33, count: 12),
        parameters: .initial
    )

    let unwrapped = try VaultKeyEnvelope.unwrap(metadata, masterPassword: "correct horse battery staple")

    #expect(unwrapped == vaultKey)
}

@Test("wrong master password reports a uniform authentication failure")
func rejectsWrongMasterPassword() throws {
    let metadata = try VaultKeyEnvelope.wrap(
        vaultKey: Data(0..<32),
        masterPassword: "correct horse battery staple",
        vaultID: Data(repeating: 0x11, count: 16),
        passwordSalt: Data(repeating: 0x22, count: 16),
        wrapNonce: Data(repeating: 0x33, count: 12),
        parameters: .initial
    )

    #expect(throws: VaultKeyEnvelopeError.authenticationFailed) {
        _ = try VaultKeyEnvelope.unwrap(metadata, masterPassword: "wrong password")
    }
}
