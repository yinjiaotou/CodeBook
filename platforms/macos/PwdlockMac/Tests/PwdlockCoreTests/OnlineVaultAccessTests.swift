import Foundation
import Testing
@testable import PwdlockCore

@Test("online vault envelope can only be unwrapped locally with its master password")
func onlineVaultAccessContract() throws {
    let created = try OnlineVaultBootstrap.create(masterPassword: "correct horse battery staple")
    #expect(try OnlineVaultAccess.unlockKey(encryptedKeyEnvelope: created.encryptedKeyEnvelope, masterPassword: "correct horse battery staple") == created.vaultKey)
    #expect(throws: OnlineVaultAccessError.authenticationFailed) {
        _ = try OnlineVaultAccess.unlockKey(encryptedKeyEnvelope: created.encryptedKeyEnvelope, masterPassword: "wrong password")
    }
}
