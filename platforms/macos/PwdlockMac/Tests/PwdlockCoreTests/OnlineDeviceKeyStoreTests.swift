import Foundation
import Testing

@Test("online device private key store uses device-only Keychain accessibility")
func onlineDeviceKeyStoreContract() throws {
    let source = try String(contentsOf: URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appending(path: "Sources/PwdlockCore/Online/OnlineDeviceKeyStore.swift"), encoding: .utf8)
    #expect(source.contains("kSecAttrAccessibleWhenUnlockedThisDeviceOnly"))
    #expect(source.contains("key.rawRepresentation"))
    #expect(!source.contains("publicSigningKey"))
}
