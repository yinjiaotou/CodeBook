import Foundation

public enum OnlineVaultAccessError: Error, Equatable { case invalidEnvelope; case authenticationFailed }

/// Opens a per-vault encrypted local cache only after decrypting the server's opaque key envelope locally.
public enum OnlineVaultAccess {
    public static func unlockKey(encryptedKeyEnvelope: String, masterPassword: String) throws -> Data {
        guard let encoded = Data(base64Encoded: encryptedKeyEnvelope) else { throw OnlineVaultAccessError.invalidEnvelope }
        do {
            return try VaultKeyEnvelope.unwrap(try VaultMetadataCodec.decode(encoded), masterPassword: masterPassword)
        } catch { throw OnlineVaultAccessError.authenticationFailed }
    }

    public static func openCache(at cacheURL: URL, encryptedKeyEnvelope: String, masterPassword: String) throws -> EncryptedDatabase {
        try EncryptedDatabase.open(at: cacheURL, vaultKey: unlockKey(encryptedKeyEnvelope: encryptedKeyEnvelope, masterPassword: masterPassword))
    }
}
