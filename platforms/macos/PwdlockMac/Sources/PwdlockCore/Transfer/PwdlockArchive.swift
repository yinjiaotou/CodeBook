import CryptoKit
import Foundation

public enum PwdlockArchiveError: Error, Equatable {
    /// This intentionally covers both an incorrect password and authenticated corruption.
    case authenticationFailed
    case invalidArchive
}

public struct PwdlockRecord: Codable, Equatable, Sendable {
    public var id: UUID
    public var type: String
    public var title: String
    public var username: String
    public var password: String
    public var url: String
    public var category: String
    public var note: String
    public var createdAtMs: Int64
    public var updatedAtMs: Int64
    public var revision: Int64
    public var deviceId: UUID

    public init(id: UUID, type: String = "login", title: String, username: String, password: String, url: String, category: String, note: String, createdAtMs: Int64, updatedAtMs: Int64, revision: Int64, deviceId: UUID) {
        self.id = id; self.type = type; self.title = title; self.username = username; self.password = password
        self.url = url; self.category = category; self.note = note; self.createdAtMs = createdAtMs
        self.updatedAtMs = updatedAtMs; self.revision = revision; self.deviceId = deviceId
    }

    enum CodingKeys: String, CodingKey {
        case id, type, title, username, password, url, category, note, createdAtMs, updatedAtMs, revision, deviceId
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.uuidString.lowercased(), forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(title, forKey: .title)
        try container.encode(username, forKey: .username)
        try container.encode(password, forKey: .password)
        try container.encode(url, forKey: .url)
        try container.encode(category, forKey: .category)
        try container.encode(note, forKey: .note)
        try container.encode(createdAtMs, forKey: .createdAtMs)
        try container.encode(updatedAtMs, forKey: .updatedAtMs)
        try container.encode(revision, forKey: .revision)
        try container.encode(deviceId.uuidString.lowercased(), forKey: .deviceId)
    }
}

public struct PwdlockPayload: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var exportId: UUID
    public var sourceVaultId: UUID
    public var createdAtMs: Int64
    public var records: [PwdlockRecord]
    public var tombstones: [PwdlockTombstone]
    public var conflictGroups: [PwdlockConflictGroup]

    public init(exportId: UUID, sourceVaultId: UUID, createdAtMs: Int64, records: [PwdlockRecord], tombstones: [PwdlockTombstone] = [], conflictGroups: [PwdlockConflictGroup] = []) {
        self.schemaVersion = 1; self.exportId = exportId; self.sourceVaultId = sourceVaultId; self.createdAtMs = createdAtMs
        self.records = records; self.tombstones = tombstones; self.conflictGroups = conflictGroups
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, exportId, sourceVaultId, createdAtMs, records, tombstones, conflictGroups
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(exportId.uuidString.lowercased(), forKey: .exportId)
        try container.encode(sourceVaultId.uuidString.lowercased(), forKey: .sourceVaultId)
        try container.encode(createdAtMs, forKey: .createdAtMs)
        try container.encode(records, forKey: .records)
        try container.encode(tombstones, forKey: .tombstones)
        try container.encode(conflictGroups, forKey: .conflictGroups)
    }
}

public struct PwdlockTombstone: Codable, Equatable, Sendable {
    public var recordId: UUID
    public var deletedAtMs: Int64
    public var revision: Int64
    public var deviceId: UUID
}

/// Conflict import/export is reserved for a later v1 application release. The byte codec rejects them for now.
public struct PwdlockConflictGroup: Codable, Equatable, Sendable {
    public var groupId: UUID
    public var recordId: UUID
    public var state: String
    public var createdAtMs: Int64
}

public enum PwdlockArchive {
    public typealias Randomness = (Int) throws -> Data
    public static let maximumFileBytes = 100 * 1_024 * 1_024

    private static let headerLength = 116
    private static let tagLength = 16
    private static let maxCiphertextBytes = maximumFileBytes
    private static let maxPlaintextBytes = 200 * 1_024 * 1_024
    private static let parameters = Argon2idParameters(memoryKiB: 65_536, iterations: 3, parallelism: 1)

    public static func export(payload: PwdlockPayload, password: String, randomness: @escaping Randomness = SecureRandom.bytes) throws -> Data {
        try validate(payload)
        let plaintext = try jsonEncoder.encode(payload)
        guard plaintext.count <= maxPlaintextBytes, plaintext.count <= maxCiphertextBytes - headerLength - tagLength else { throw PwdlockArchiveError.invalidArchive }

        let salt = try random(randomness, count: 16)
        let wrapNonce = try random(randomness, count: 12)
        let exportKey = try random(randomness, count: 32)
        let payloadNonce = try random(randomness, count: 12)
        var header = headerPrefix(salt: salt, wrapNonce: wrapNonce)
        let kek = try Argon2id.deriveKey(password: PasswordInput.utf8NFC(password), salt: salt, parameters: parameters)
        let wrapped = try AES.GCM.seal(exportKey, using: SymmetricKey(data: kek), nonce: AES.GCM.Nonce(data: wrapNonce), authenticating: header.prefix(36))
        guard wrapped.ciphertext.count == 32, wrapped.tag.count == tagLength else { throw PwdlockArchiveError.invalidArchive }
        header.append(wrapped.ciphertext)
        header.append(wrapped.tag)
        header.append(payloadNonce)
        header.appendUInt64(UInt64(plaintext.count))
        let encrypted = try AES.GCM.seal(plaintext, using: SymmetricKey(data: exportKey), nonce: AES.GCM.Nonce(data: payloadNonce), authenticating: header)
        guard encrypted.ciphertext.count == plaintext.count, encrypted.tag.count == tagLength else { throw PwdlockArchiveError.invalidArchive }
        header.append(encrypted.ciphertext)
        header.append(encrypted.tag)
        return header
    }

    public static func `import`(data: Data, password: String) throws -> PwdlockPayload {
        let header = try parseHeader(data)
        let plaintext: Data
        do {
            let kek = try Argon2id.deriveKey(password: PasswordInput.utf8NFC(password), salt: header.salt, parameters: header.parameters)
            let wrapped = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: header.wrapNonce), ciphertext: header.wrappedKey, tag: header.wrapTag)
            let exportKey = try AES.GCM.open(wrapped, using: SymmetricKey(data: kek), authenticating: data.prefix(36))
            guard exportKey.count == 32 else { throw PwdlockArchiveError.authenticationFailed }
            let payloadBox = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: header.payloadNonce), ciphertext: header.ciphertext, tag: header.payloadTag)
            plaintext = try AES.GCM.open(payloadBox, using: SymmetricKey(data: exportKey), authenticating: data.prefix(headerLength))
            guard plaintext.count <= maxPlaintextBytes else { throw PwdlockArchiveError.invalidArchive }
        } catch let error as PwdlockArchiveError { throw error }
        catch { throw PwdlockArchiveError.authenticationFailed }
        do {
            try StrictJSONValidator.validate(plaintext)
            try validateJSONShape(plaintext)
            let payload = try jsonDecoder.decode(PwdlockPayload.self, from: plaintext)
            try validate(payload)
            return payload
        } catch let error as PwdlockArchiveError { throw error }
        catch { throw PwdlockArchiveError.invalidArchive }
    }

    private static func random(_ source: Randomness, count: Int) throws -> Data {
        let bytes = try source(count)
        guard bytes.count == count else { throw PwdlockArchiveError.invalidArchive }
        return bytes
    }

    private static func headerPrefix(salt: Data, wrapNonce: Data) -> Data {
        var data = Data("PWLK".utf8)
        data.append(contentsOf: [1, 1, 1, 0])
        data.appendUInt32(parameters.memoryKiB)
        data.appendUInt32(parameters.iterations)
        data.append(UInt8(parameters.parallelism))
        data.append(contentsOf: [0, 0, 0])
        data.append(salt)
        data.append(wrapNonce)
        return data
    }

    private struct Header {
        let parameters: Argon2idParameters
        let salt, wrapNonce, wrappedKey, wrapTag, payloadNonce, ciphertext, payloadTag: Data
    }

    private static func parseHeader(_ data: Data) throws -> Header {
        guard data.count <= maxCiphertextBytes, data.count >= headerLength else { throw PwdlockArchiveError.invalidArchive }
        guard data.prefix(4) == Data("PWLK".utf8), data[4] == 1, data[5] == 1, data[6] == 1, data[7] == 0,
              data[17] == 0, data[18] == 0, data[19] == 0 else { throw PwdlockArchiveError.invalidArchive }
        let memory = data.uint32(at: 8), iterations = data.uint32(at: 12), lanes = UInt32(data[16])
        guard (65_536...262_144).contains(memory), (3...10).contains(iterations), (1...4).contains(lanes) else { throw PwdlockArchiveError.invalidArchive }
        let length = data.uint64(at: 108)
        guard length <= UInt64(maxCiphertextBytes), length <= UInt64(Int.max - headerLength - tagLength) else { throw PwdlockArchiveError.invalidArchive }
        let expected = headerLength + Int(length) + tagLength
        if data.count < expected { throw PwdlockArchiveError.authenticationFailed }
        guard data.count == expected else { throw PwdlockArchiveError.invalidArchive }
        return Header(parameters: .init(memoryKiB: memory, iterations: iterations, parallelism: lanes), salt: data.subdata(in: 20..<36), wrapNonce: data.subdata(in: 36..<48), wrappedKey: data.subdata(in: 48..<80), wrapTag: data.subdata(in: 80..<96), payloadNonce: data.subdata(in: 96..<108), ciphertext: data.subdata(in: headerLength..<(headerLength + Int(length))), payloadTag: data.suffix(tagLength))
    }

    private static func validate(_ payload: PwdlockPayload) throws {
        guard payload.schemaVersion == 1, validTimestamp(payload.createdAtMs), payload.records.count <= 100_000, payload.tombstones.isEmpty, payload.conflictGroups.isEmpty else { throw PwdlockArchiveError.invalidArchive }
        var recordIDs = Set<UUID>()
        for record in payload.records {
            guard recordIDs.insert(record.id).inserted, record.type == "login", validTimestamp(record.createdAtMs), validTimestamp(record.updatedAtMs), record.createdAtMs <= record.updatedAtMs, validRevision(record.revision), validString(record.title, 1...256), validString(record.username, 0...2_048), validString(record.password, 0...4_096), validString(record.url, 0...2_048), validString(record.category, 0...2_048), validString(record.note, 0...16_384) else { throw PwdlockArchiveError.invalidArchive }
        }
    }

    private static func validateJSONShape(_ plaintext: Data) throws {
        guard String(data: plaintext, encoding: .utf8) != nil,
              let root = try JSONSerialization.jsonObject(with: plaintext) as? [String: Any],
              Set(root.keys) == ["schemaVersion", "exportId", "sourceVaultId", "createdAtMs", "records", "tombstones", "conflictGroups"],
              let records = root["records"] as? [[String: Any]],
              let tombstones = root["tombstones"] as? [Any], tombstones.isEmpty,
              let conflicts = root["conflictGroups"] as? [Any], conflicts.isEmpty else {
            throw PwdlockArchiveError.invalidArchive
        }
        let recordKeys: Set<String> = ["id", "type", "title", "username", "password", "url", "category", "note", "createdAtMs", "updatedAtMs", "revision", "deviceId"]
        guard records.allSatisfy({ Set($0.keys) == recordKeys }) else { throw PwdlockArchiveError.invalidArchive }
    }

    private static func validTimestamp(_ value: Int64) -> Bool { value >= 0 }
    private static func validRevision(_ value: Int64) -> Bool { (0...9_007_199_254_740_991).contains(value) }
    private static func validString(_ value: String, _ count: ClosedRange<Int>) -> Bool {
        !value.unicodeScalars.contains("\0") && value == value.precomposedStringWithCanonicalMapping && count.contains(value.unicodeScalars.count)
    }

    private static let jsonEncoder: JSONEncoder = { let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; return encoder }()
    private static let jsonDecoder = JSONDecoder()
}

/// JSONDecoder and JSONSerialization both collapse duplicate object keys. This small
/// authenticated-plaintext parser preserves key occurrences long enough to reject
/// duplicates and enforce the protocol's lowercase canonical UUID representation.
private struct StrictJSONValidator {
    private static let uuidFieldNames: Set<String> = [
        "exportId", "sourceVaultId", "id", "deviceId", "recordId", "groupId"
    ]

    private let bytes: [UInt8]
    private var index = 0

    static func validate(_ data: Data) throws {
        var validator = StrictJSONValidator(bytes: Array(data))
        try validator.parseDocument()
    }

    private mutating func parseDocument() throws {
        try skipWhitespace()
        try parseValue(uuidField: false)
        try skipWhitespace()
        guard index == bytes.count else { throw PwdlockArchiveError.invalidArchive }
    }

    private mutating func parseValue(uuidField: Bool) throws {
        try skipWhitespace()
        guard index < bytes.count else { throw PwdlockArchiveError.invalidArchive }
        if uuidField, bytes[index] != 0x22 { throw PwdlockArchiveError.invalidArchive }
        switch bytes[index] {
        case 0x7b: try parseObject() // {
        case 0x5b: try parseArray() // [
        case 0x22: // "
            let value = try parseString()
            if uuidField, !isRawLowercaseCanonicalUUID(value) {
                throw PwdlockArchiveError.invalidArchive
            }
        case 0x74: try consumeLiteral("true")
        case 0x66: try consumeLiteral("false")
        case 0x6e: try consumeLiteral("null")
        default: try parseNumber()
        }
    }

    private mutating func parseObject() throws {
        try consume(0x7b)
        try skipWhitespace()
        if try consumeIf(0x7d) { return }
        var keys = Set<String>()
        while true {
            guard index < bytes.count, bytes[index] == 0x22 else { throw PwdlockArchiveError.invalidArchive }
            let key = try parseString().value
            guard keys.insert(key).inserted else { throw PwdlockArchiveError.invalidArchive }
            try skipWhitespace()
            try consume(0x3a)
            try parseValue(uuidField: Self.uuidFieldNames.contains(key))
            try skipWhitespace()
            if try consumeIf(0x7d) { return }
            try consume(0x2c)
            try skipWhitespace()
        }
    }

    private mutating func parseArray() throws {
        try consume(0x5b)
        try skipWhitespace()
        if try consumeIf(0x5d) { return }
        while true {
            try parseValue(uuidField: false)
            try skipWhitespace()
            if try consumeIf(0x5d) { return }
            try consume(0x2c)
            try skipWhitespace()
        }
    }

    private mutating func parseString() throws -> ParsedString {
        let start = index
        try consume(0x22)
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if byte == 0x22 {
                let token = Data(bytes[start..<index])
                guard let value = try? JSONSerialization.jsonObject(with: token, options: [.fragmentsAllowed]) as? String else {
                    throw PwdlockArchiveError.invalidArchive
                }
                return ParsedString(value: value, rawToken: token)
            }
            guard byte >= 0x20 else { throw PwdlockArchiveError.invalidArchive }
            if byte == 0x5c { // \
                guard index < bytes.count else { throw PwdlockArchiveError.invalidArchive }
                let escape = bytes[index]
                index += 1
                switch escape {
                case 0x22, 0x5c, 0x2f, 0x62, 0x66, 0x6e, 0x72, 0x74: break
                case 0x75:
                    for _ in 0..<4 {
                        guard index < bytes.count, isHexDigit(bytes[index]) else {
                            throw PwdlockArchiveError.invalidArchive
                        }
                        index += 1
                    }
                default: throw PwdlockArchiveError.invalidArchive
                }
            }
        }
        throw PwdlockArchiveError.invalidArchive
    }

    private mutating func parseNumber() throws {
        if try consumeIf(0x2d) {} // -
        guard index < bytes.count else { throw PwdlockArchiveError.invalidArchive }
        if try consumeIf(0x30) { // 0
            guard index == bytes.count || !isDigit(bytes[index]) else { throw PwdlockArchiveError.invalidArchive }
        } else {
            guard isNonzeroDigit(bytes[index]) else { throw PwdlockArchiveError.invalidArchive }
            index += 1
            while index < bytes.count, isDigit(bytes[index]) { index += 1 }
        }
        if try consumeIf(0x2e) { // .
            try consumeDigits()
        }
        if index < bytes.count, bytes[index] == 0x65 || bytes[index] == 0x45 { // e E
            index += 1
            if index < bytes.count, bytes[index] == 0x2b || bytes[index] == 0x2d { index += 1 }
            try consumeDigits()
        }
    }

    private mutating func consumeDigits() throws {
        guard index < bytes.count, isDigit(bytes[index]) else { throw PwdlockArchiveError.invalidArchive }
        while index < bytes.count, isDigit(bytes[index]) { index += 1 }
    }

    private mutating func consumeLiteral(_ literal: String) throws {
        let literalBytes = Array(literal.utf8)
        guard bytes[index...].starts(with: literalBytes) else { throw PwdlockArchiveError.invalidArchive }
        index += literalBytes.count
    }

    private mutating func skipWhitespace() throws {
        while index < bytes.count, [0x20, 0x0a, 0x0d, 0x09].contains(bytes[index]) {
            index += 1
        }
    }

    private mutating func consume(_ byte: UInt8) throws {
        guard try consumeIf(byte) else { throw PwdlockArchiveError.invalidArchive }
    }

    private mutating func consumeIf(_ byte: UInt8) throws -> Bool {
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1
        return true
    }

    private func isRawLowercaseCanonicalUUID(_ parsedString: ParsedString) -> Bool {
        let characters = Array(parsedString.value.utf8)
        guard parsedString.rawToken == Data(("\"\(parsedString.value)\"").utf8),
              characters.count == 36,
              UUID(uuidString: parsedString.value) != nil else { return false }
        for (offset, character) in characters.enumerated() {
            if [8, 13, 18, 23].contains(offset) {
                guard character == 0x2d else { return false }
            } else if !isLowercaseHexDigit(character) {
                return false
            }
        }
        return true
    }

    private struct ParsedString {
        let value: String
        let rawToken: Data
    }

    private func isDigit(_ byte: UInt8) -> Bool { (0x30...0x39).contains(byte) }
    private func isNonzeroDigit(_ byte: UInt8) -> Bool { (0x31...0x39).contains(byte) }
    private func isHexDigit(_ byte: UInt8) -> Bool {
        isDigit(byte) || (0x41...0x46).contains(byte) || (0x61...0x66).contains(byte)
    }
    private func isLowercaseHexDigit(_ byte: UInt8) -> Bool {
        isDigit(byte) || (0x61...0x66).contains(byte)
    }
}

private extension Data {
    mutating func appendUInt32(_ value: UInt32) { append(contentsOf: [UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16), UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)]) }
    mutating func appendUInt64(_ value: UInt64) { append(contentsOf: (0..<8).reversed().map { UInt8((value >> UInt64($0 * 8)) & 0xff) }) }
    func uint32(at offset: Int) -> UInt32 { self[offset..<(offset + 4)].reduce(0) { ($0 << 8) | UInt32($1) } }
    func uint64(at offset: Int) -> UInt64 { self[offset..<(offset + 8)].reduce(0) { ($0 << 8) | UInt64($1) } }
}
