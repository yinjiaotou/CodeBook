import Foundation
import Testing
@testable import PwdlockCore

@Test("online vault bootstrap exposes only an encrypted key envelope and raw device public key")
func onlineVaultBootstrapContract() throws {
    let vault = try OnlineVaultBootstrap.create(masterPassword: "correct horse battery staple")
    #expect(vault.vaultKey.count == 32)
    #expect(Data(base64Encoded: vault.encryptedKeyEnvelope) != nil)
    #expect(Data(base64Encoded: vault.publicSigningKey)?.count == 32)
    #expect(vault.encryptedKeyEnvelope != vault.vaultKey.base64EncodedString())
}
