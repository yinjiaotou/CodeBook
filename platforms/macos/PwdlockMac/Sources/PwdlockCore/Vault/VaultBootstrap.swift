import Foundation

public struct CreatedVault: Sendable {
    public let metadata: VaultMetadata
    public let vaultKey: Data
}

public enum VaultBootstrap {
    public static func create(masterPassword: String) throws -> CreatedVault {
        let vaultKey = try SecureRandom.bytes(count: 32)
        let metadata = try VaultKeyEnvelope.wrap(
            vaultKey: vaultKey,
            masterPassword: masterPassword,
            vaultID: SecureRandom.bytes(count: 16),
            passwordSalt: SecureRandom.bytes(count: 16),
            wrapNonce: SecureRandom.bytes(count: 12),
            parameters: .initial
        )
        return CreatedVault(metadata: metadata, vaultKey: vaultKey)
    }
}
