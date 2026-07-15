import CryptoKit
import Foundation
import Testing
@testable import PwdlockCore

@Test("online change encrypts every login field before it leaves the client")
func onlineVaultChangeContract() throws {
    let item = LoginItem(id: UUID(), title: "银行", username: "alice", password: "secret", url: "https://bank.test", category: "金融", note: "note", createdAt: Date(), updatedAt: Date(), revision: 1, deviceID: UUID())
    let key = Data(repeating: 7, count: 32), signingKey = Curve25519.Signing.PrivateKey()
    let envelope = try OnlineVaultChangeCodec.seal(OnlineVaultChange(operation: .upsert, item: item), vaultID: UUID(), changeID: UUID(), vaultKey: key, signingKey: signingKey)
    #expect(!envelope.ciphertext.contains("secret"))
    #expect(!envelope.ciphertext.contains("银行"))
}

@Test("downloaded online change verifies its device signature before decoding")
func downloadedOnlineVaultChangeContract() throws {
    let vaultID = UUID(), changeID = UUID(), key = Data(repeating: 8, count: 32), signingKey = Curve25519.Signing.PrivateKey()
    let item = LoginItem(id: UUID(), title: "项目", username: "a", password: "p", url: "", category: "", note: "", createdAt: Date(), updatedAt: Date(), revision: 0, deviceID: UUID())
    let envelope = try OnlineVaultChangeCodec.seal(OnlineVaultChange(operation: .upsert, item: item), vaultID: vaultID, changeID: changeID, vaultKey: key, signingKey: signingKey)
    let remote = OnlineRemoteChange(sequence: "1", changeId: changeID.uuidString, deviceId: UUID(), ciphertext: envelope.ciphertext, signature: envelope.signature)
    let decoded = try OnlineVaultChangeCodec.open(remote, vaultID: vaultID, vaultKey: key, publicSigningKey: signingKey.publicKey)
    #expect(decoded.item.id == item.id)
    #expect(decoded.item.password == item.password)
}
