import CryptoKit
import Foundation

/// Complete password-record mutation. This structure is encoded only before encryption.
public struct OnlineVaultChange: Codable, Sendable, Equatable {
    public enum Operation: String, Codable, Sendable { case upsert, delete }
    public let operation: Operation
    public let item: LoginItem
    public let previousChangeDigest: String?

    public init(operation: Operation, item: LoginItem, previousChangeDigest: String? = nil) {
        self.operation = operation
        self.item = item
        self.previousChangeDigest = previousChangeDigest
    }
}

public enum OnlineVaultChangeCodec {
    public static func seal(_ change: OnlineVaultChange, vaultID: UUID, changeID: UUID, vaultKey: Data, signingKey: Curve25519.Signing.PrivateKey) throws -> OnlineSyncEnvelope {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try OnlineSyncEnvelope.seal(plaintext: encoder.encode(change), vaultID: vaultID, changeID: changeID, vaultKey: vaultKey, signingKey: signingKey)
    }
}
