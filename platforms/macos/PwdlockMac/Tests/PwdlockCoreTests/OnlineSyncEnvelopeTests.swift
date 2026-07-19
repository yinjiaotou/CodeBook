import CryptoKit
import Foundation
import Testing
@testable import PwdlockCore

private let syncVaultID = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
private let syncChangeID = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!

@Test("online sync envelope encrypts and signs a change using client-only key material")
func onlineSyncEnvelopeRoundTrips() throws {
    let vaultKey = Data(repeating: 0x11, count: 32)
    let signingKey = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: 0x22, count: 32))
    let plaintext = Data("synthetic encrypted login change".utf8)

    let envelope = try OnlineSyncEnvelope.seal(
        plaintext: plaintext,
        vaultID: syncVaultID,
        changeID: syncChangeID,
        vaultKey: vaultKey,
        nonce: Data(repeating: 0x33, count: 12),
        signingKey: signingKey
    )

    #expect(envelope.ciphertext != plaintext.base64EncodedString())
    #expect(try OnlineSyncEnvelope.open(
        envelope,
        vaultID: syncVaultID,
        vaultKey: vaultKey,
        publicSigningKey: signingKey.publicKey
    ) == plaintext)
}

@Test("online sync envelope rejects a mismatched signature or associated IDs")
func onlineSyncEnvelopeRejectsTampering() throws {
    let vaultKey = Data(repeating: 0x44, count: 32)
    let signingKey = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: 0x55, count: 32))
    let envelope = try OnlineSyncEnvelope.seal(
        plaintext: Data("synthetic".utf8), vaultID: syncVaultID, changeID: syncChangeID,
        vaultKey: vaultKey, nonce: Data(repeating: 0x66, count: 12), signingKey: signingKey
    )
    let altered = OnlineSyncEnvelope(
        ciphertext: envelope.ciphertext,
        signature: Data(repeating: 0x00, count: 64).base64EncodedString()
    )

    #expect(throws: OnlineSyncEnvelopeError.authenticationFailed) {
        _ = try OnlineSyncEnvelope.open(altered, vaultID: syncVaultID, vaultKey: vaultKey, publicSigningKey: signingKey.publicKey)
    }
    #expect(throws: OnlineSyncEnvelopeError.authenticationFailed) {
        _ = try OnlineSyncEnvelope.open(envelope, vaultID: UUID(), vaultKey: vaultKey, publicSigningKey: signingKey.publicKey)
    }
}
