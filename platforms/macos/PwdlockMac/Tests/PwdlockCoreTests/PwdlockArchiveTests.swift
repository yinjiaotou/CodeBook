import CryptoKit
import Foundation
import Testing
@testable import PwdlockCore

@Test("pwdlock archive round-trips a login payload and writes the fixed v1 header")
func archiveRoundTripAndHeader() throws {
    let payload = archivePayload()
    let random = deterministicRandomness()
    let archive = try PwdlockArchive.export(payload: payload, password: "export password", randomness: random.next)

    #expect(archive.count > 132)
    #expect(archive.prefix(4) == Data("PWLK".utf8))
    #expect(archive[4] == 1)
    #expect(archive[5] == 1)
    #expect(archive[6] == 1)
    #expect(archive[7] == 0)
    #expect(archive[8..<12] == Data([0, 1, 0, 0]))
    #expect(archive[12..<16] == Data([0, 0, 0, 3]))
    #expect(archive[16] == 1)
    #expect(archive[17..<20] == Data(repeating: 0, count: 3))
    #expect(try PwdlockArchive.import(data: archive, password: "export password") == payload)
}

@Test("pwdlock archive makes password and authenticated tampering indistinguishable")
func archiveAuthenticationFailuresAreUniform() throws {
    let archive = try PwdlockArchive.export(payload: archivePayload(), password: "right", randomness: deterministicRandomness().next)
    var tampered = archive
    tampered[tampered.index(before: tampered.endIndex)] ^= 0x01

    #expect(throws: PwdlockArchiveError.authenticationFailed) {
        try PwdlockArchive.import(data: archive, password: "wrong")
    }
    #expect(throws: PwdlockArchiveError.authenticationFailed) {
        try PwdlockArchive.import(data: tampered, password: "right")
    }
}

@Test("pwdlock archive rejects invalid size declarations and trailing bytes")
func archiveRejectsInvalidContainerSizes() throws {
    let archive = try PwdlockArchive.export(payload: archivePayload(), password: "right", randomness: deterministicRandomness().next)
    var excessive = archive
    excessive.replaceSubrange(108..<116, with: Data([0, 0, 0, 0, 6, 64, 0, 1]))
    #expect(throws: PwdlockArchiveError.invalidArchive) {
        try PwdlockArchive.import(data: excessive, password: "right")
    }
    #expect(throws: PwdlockArchiveError.invalidArchive) {
        try PwdlockArchive.import(data: archive + Data([0]), password: "right")
    }
    #expect(throws: PwdlockArchiveError.authenticationFailed) {
        try PwdlockArchive.import(data: archive.dropLast(), password: "right")
    }
}

@Test("pwdlock archive validates authenticated payload schema")
func archiveRejectsInvalidPayloadSchema() throws {
    var invalid = archivePayload()
    invalid.records[0].title = ""
    #expect(throws: PwdlockArchiveError.invalidArchive) {
        try PwdlockArchive.export(payload: invalid, password: "right", randomness: deterministicRandomness().next)
    }
}

@Test("pwdlock archive rejects duplicate JSON keys at both root and record object levels")
func archiveRejectsDuplicateJSONKeys() throws {
    let validJSON = validArchiveJSON()
    let duplicateRootKey = validJSON.replacingOccurrences(
        of: "\"schemaVersion\":1,",
        with: "\"schemaVersion\":1,\"schemaVersion\":1,"
    )
    let duplicateRecordKey = validJSON.replacingOccurrences(
        of: "\"title\":\"Example\",",
        with: "\"title\":\"Example\",\"title\":\"Duplicate\","
    )

    #expect(throws: PwdlockArchiveError.invalidArchive) {
        try PwdlockArchive.import(data: rawJSONArchive(duplicateRootKey), password: "right")
    }
    #expect(throws: PwdlockArchiveError.invalidArchive) {
        try PwdlockArchive.import(data: rawJSONArchive(duplicateRecordKey), password: "right")
    }
}

@Test("pwdlock archive requires lowercase canonical UUID strings in authenticated JSON")
func archiveRejectsUppercaseUUIDStrings() throws {
    let uppercaseUUID = validArchiveJSON().replacingOccurrences(
        of: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        with: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"
    )

    #expect(throws: PwdlockArchiveError.invalidArchive) {
        try PwdlockArchive.import(data: rawJSONArchive(uppercaseUUID), password: "right")
    }
    let escapedUUID = validArchiveJSON().replacingOccurrences(
        of: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        with: "\\u0061aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    )
    #expect(throws: PwdlockArchiveError.invalidArchive) {
        try PwdlockArchive.import(data: rawJSONArchive(escapedUUID), password: "right")
    }
}

private func archivePayload() -> PwdlockPayload {
    PwdlockPayload(
        exportId: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!,
        sourceVaultId: UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!,
        createdAtMs: 1_760_000_000_000,
        records: [
            PwdlockRecord(
                id: UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")!, title: "Example", username: "name@example.com",
                password: "secret", url: "https://example.com", category: "Personal", note: "", createdAtMs: 1_760_000_000_000,
                updatedAtMs: 1_760_000_000_001, revision: 0, deviceId: UUID(uuidString: "dddddddd-dddd-4ddd-8ddd-dddddddddddd")!
            )
        ]
    )
}

private final class DeterministicRandomness {
    private var value: UInt8 = 0
    func next(count: Int) throws -> Data {
        defer { value &+= 1 }
        return Data(repeating: value, count: count)
    }
}

private func deterministicRandomness() -> DeterministicRandomness { DeterministicRandomness() }

private func validArchiveJSON() -> String {
    #"""
    {"schemaVersion":1,"exportId":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","sourceVaultId":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","createdAtMs":1760000000000,"records":[{"id":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","type":"login","title":"Example","username":"name@example.com","password":"secret","url":"https://example.com","category":"Personal","note":"","createdAtMs":1760000000000,"updatedAtMs":1760000000001,"revision":0,"deviceId":"dddddddd-dddd-4ddd-8ddd-dddddddddddd"}],"tombstones":[],"conflictGroups":[]}
    """#
}

private func rawJSONArchive(_ json: String, password: String = "right") throws -> Data {
    let plaintext = Data(json.utf8)
    let salt = Data(repeating: 0x11, count: 16)
    let wrapNonce = Data(repeating: 0x22, count: 12)
    let exportKey = Data(repeating: 0x33, count: 32)
    let payloadNonce = Data(repeating: 0x44, count: 12)
    var header = Data("PWLK".utf8)
    header.append(contentsOf: [1, 1, 1, 0])
    header.append(contentsOf: [0, 1, 0, 0, 0, 0, 0, 3, 1, 0, 0, 0])
    header.append(salt)
    header.append(wrapNonce)
    let key = try Argon2id.deriveKey(
        password: Data(password.utf8),
        salt: salt,
        parameters: Argon2idParameters(memoryKiB: 65_536, iterations: 3, parallelism: 1)
    )
    let wrapped = try AES.GCM.seal(
        exportKey,
        using: SymmetricKey(data: key),
        nonce: AES.GCM.Nonce(data: wrapNonce),
        authenticating: header.prefix(36)
    )
    header.append(wrapped.ciphertext)
    header.append(wrapped.tag)
    header.append(payloadNonce)
    var length = UInt64(plaintext.count).bigEndian
    withUnsafeBytes(of: &length) { header.append(contentsOf: $0) }
    let encrypted = try AES.GCM.seal(
        plaintext,
        using: SymmetricKey(data: exportKey),
        nonce: AES.GCM.Nonce(data: payloadNonce),
        authenticating: header
    )
    header.append(encrypted.ciphertext)
    header.append(encrypted.tag)
    return header
}
