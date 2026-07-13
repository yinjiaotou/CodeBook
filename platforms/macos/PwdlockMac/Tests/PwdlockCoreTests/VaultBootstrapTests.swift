import Foundation
import Testing
@testable import PwdlockCore

@Test("new vault creation generates a 32-byte key that the master password can unwrap")
func createsUnlockableVault() throws {
    let created = try VaultBootstrap.create(masterPassword: "correct horse battery staple")

    #expect(created.vaultKey.count == 32)
    #expect(created.metadata.vaultID.count == 16)
    #expect(created.metadata.passwordSalt.count == 16)
    #expect(created.metadata.wrapNonce.count == 12)
    #expect(try VaultKeyEnvelope.unwrap(created.metadata, masterPassword: "correct horse battery staple") == created.vaultKey)
}
