import Foundation
import Testing
@testable import PwdlockCore

@Test("Argon2id derives the RFC-compatible fixed test vector")
func derivesKnownArgon2idVector() throws {
    let output = try Argon2id.deriveKey(
        password: Data("password".utf8),
        salt: Data("somesalt".utf8),
        parameters: .init(memoryKiB: 65_536, iterations: 3, parallelism: 1)
    )

    #expect(output.hexString == "9e8789c8b42834220afc00085ac73acc308651216994abbfddd69b2592032efd")
}

private extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
