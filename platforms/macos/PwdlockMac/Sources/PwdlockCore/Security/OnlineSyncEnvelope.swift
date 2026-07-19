import CryptoKit
import Foundation

/// An opaque, client-side encrypted change ready for upload to the sync service.
/// The server stores `ciphertext` and `signature` without inspecting their contents.
public struct OnlineSyncEnvelope: Sendable, Equatable {
    public let ciphertext: String
    public let signature: String
    /// Kept locally with an envelope so it can be authenticated again on download.
    /// It is sent as the protocol's separate opaque `changeId` field.
    public let changeID: UUID?

    public init(ciphertext: String, signature: String, changeID: UUID? = nil) {
        self.ciphertext = ciphertext
        self.signature = signature
        self.changeID = changeID
    }
}

public enum OnlineSyncEnvelopeError: Error, Equatable {
    case invalidVaultKey
    case authenticationFailed
}

public extension OnlineSyncEnvelope {
    private static var protocolLabel: String { "pwdlock.sync.v1" }
    private static var encryptionContext: String { "pwdlock.sync.v1.change" }

    static func seal(
        plaintext: Data,
        vaultID: UUID,
        changeID: UUID,
        vaultKey: Data,
        nonce: Data? = nil,
        signingKey: Curve25519.Signing.PrivateKey
    ) throws -> OnlineSyncEnvelope {
        guard vaultKey.count == 32 else { throw OnlineSyncEnvelopeError.invalidVaultKey }

        do {
            let sealingNonce: AES.GCM.Nonce
            if let nonce {
                sealingNonce = try AES.GCM.Nonce(data: nonce)
            } else {
                sealingNonce = AES.GCM.Nonce()
            }
            let sealed = try AES.GCM.seal(
                plaintext,
                using: changeKey(from: vaultKey),
                nonce: sealingNonce,
                authenticating: associatedData(vaultID: vaultID, changeID: changeID)
            )
            guard let combined = sealed.combined else {
                throw OnlineSyncEnvelopeError.authenticationFailed
            }
            let ciphertext = combined.base64EncodedString()
            let signature = try signingKey.signature(for: signatureMessage(
                vaultID: vaultID,
                changeID: changeID,
                ciphertext: ciphertext
            )).base64EncodedString()
            return OnlineSyncEnvelope(ciphertext: ciphertext, signature: signature, changeID: changeID)
        } catch {
            throw OnlineSyncEnvelopeError.authenticationFailed
        }
    }

    static func open(
        _ envelope: OnlineSyncEnvelope,
        vaultID: UUID,
        vaultKey: Data,
        publicSigningKey: Curve25519.Signing.PublicKey
    ) throws -> Data {
        guard vaultKey.count == 32 else { throw OnlineSyncEnvelopeError.invalidVaultKey }
        guard let changeID = envelope.changeID,
              let combined = Data(base64Encoded: envelope.ciphertext),
              let signature = Data(base64Encoded: envelope.signature),
              publicSigningKey.isValidSignature(signature, for: signatureMessage(
                  vaultID: vaultID,
                  changeID: changeID,
                  ciphertext: envelope.ciphertext
              )) else {
            throw OnlineSyncEnvelopeError.authenticationFailed
        }

        do {
            let sealed = try AES.GCM.SealedBox(combined: combined)
            return try AES.GCM.open(
                sealed,
                using: changeKey(from: vaultKey),
                authenticating: associatedData(vaultID: vaultID, changeID: changeID)
            )
        } catch {
            // Android builds released before the cross-platform envelope fix
            // sent `ciphertext || tag` without the deterministic nonce prefix.
            // Their nonce can be recovered from the authenticated change ID, so
            // accept that legacy wire format only after normal decoding fails.
            do {
                let legacyNonce = Data(SHA256.hash(data: Data(changeID.uuidString.lowercased().utf8)).prefix(12))
                guard combined.count >= 16 else { throw OnlineSyncEnvelopeError.authenticationFailed }
                let legacyBox = try AES.GCM.SealedBox(
                    nonce: AES.GCM.Nonce(data: legacyNonce),
                    ciphertext: combined.dropLast(16),
                    tag: combined.suffix(16)
                )
                return try AES.GCM.open(
                    legacyBox,
                    using: changeKey(from: vaultKey),
                    authenticating: associatedData(vaultID: vaultID, changeID: changeID)
                )
            } catch {
                throw OnlineSyncEnvelopeError.authenticationFailed
            }
        }
    }

    private static func changeKey(from vaultKey: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: vaultKey),
            salt: Data(),
            info: Data(encryptionContext.utf8),
            outputByteCount: 32
        )
    }

    private static func associatedData(vaultID: UUID, changeID: UUID) -> Data {
        Data("\(protocolLabel) | \(vaultID.uuidString.lowercased()) | \(changeID.uuidString.lowercased())".utf8)
    }

    private static func signatureMessage(vaultID: UUID, changeID: UUID, ciphertext: String) -> Data {
        Data("\(protocolLabel)\u{0}\(vaultID.uuidString.lowercased())\u{0}\(changeID.uuidString.lowercased())\u{0}\(ciphertext)".utf8)
    }
}
