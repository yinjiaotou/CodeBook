import CryptoKit
import Foundation

/// Client-only setup material. The server receives only `encryptedKeyEnvelope`.
public struct CreatedOnlineVault: Sendable {
    public let vaultKey: Data
    public let encryptedKeyEnvelope: String
    public let deviceSigningKey: Curve25519.Signing.PrivateKey

    public var publicSigningKey: String { deviceSigningKey.publicKey.rawRepresentation.base64EncodedString() }
}

public enum OnlineVaultBootstrap {
    public static func create(masterPassword: String) throws -> CreatedOnlineVault {
        let created = try VaultBootstrap.create(masterPassword: masterPassword)
        return CreatedOnlineVault(
            vaultKey: created.vaultKey,
            encryptedKeyEnvelope: try VaultMetadataCodec.encode(created.metadata).base64EncodedString(),
            deviceSigningKey: Curve25519.Signing.PrivateKey()
        )
    }
}
