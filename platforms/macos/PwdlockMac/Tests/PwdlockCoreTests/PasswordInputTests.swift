import Foundation
import Testing
@testable import PwdlockCore

@Test("password input is normalized to NFC before UTF-8 encoding")
func normalizesPasswordToNFC() {
    let decomposed = "cafe\u{301}"

    #expect(PasswordInput.utf8NFC(decomposed) == Data("café".utf8))
}

@Test("secure random bytes have the requested length")
func generatesSecureRandomBytes() throws {
    let bytes = try SecureRandom.bytes(count: 32)

    #expect(bytes.count == 32)
}
