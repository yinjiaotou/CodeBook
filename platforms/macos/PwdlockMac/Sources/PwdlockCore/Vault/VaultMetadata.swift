import Foundation

public struct VaultMetadata: Sendable, Equatable {
    public let vaultID: Data
    public let memoryKiB: UInt32
    public let iterations: UInt32
    public let parallelism: UInt8
    public let passwordSalt: Data
    public let wrapNonce: Data
    public let wrappedVaultKey: Data
    public let wrapTag: Data

    public init(
        vaultID: Data,
        memoryKiB: UInt32,
        iterations: UInt32,
        parallelism: UInt8,
        passwordSalt: Data,
        wrapNonce: Data,
        wrappedVaultKey: Data,
        wrapTag: Data
    ) {
        self.vaultID = vaultID
        self.memoryKiB = memoryKiB
        self.iterations = iterations
        self.parallelism = parallelism
        self.passwordSalt = passwordSalt
        self.wrapNonce = wrapNonce
        self.wrappedVaultKey = wrappedVaultKey
        self.wrapTag = wrapTag
    }
}

public enum VaultMetadataError: Error, Equatable {
    case invalidMagic
    case unsupportedVersion
    case unsupportedAlgorithm
    case invalidFlags
    case invalidReservedBytes
    case invalidLength
}

public enum VaultMetadataCodec {
    private static let encodedLength = 112

    public static func encode(_ metadata: VaultMetadata) throws -> Data {
        guard metadata.vaultID.count == 16,
              metadata.passwordSalt.count == 16,
              metadata.wrapNonce.count == 12,
              metadata.wrappedVaultKey.count == 32,
              metadata.wrapTag.count == 16 else {
            throw VaultMetadataError.invalidLength
        }

        var bytes = Data("PVLT".utf8)
        bytes.append(0x01)
        bytes.append(metadata.vaultID)
        bytes.append(0x01)
        bytes.append(0x01)
        bytes.append(0x00)
        appendBigEndian(metadata.memoryKiB, to: &bytes)
        appendBigEndian(metadata.iterations, to: &bytes)
        bytes.append(metadata.parallelism)
        bytes.append(contentsOf: [0x00, 0x00, 0x00])
        bytes.append(metadata.passwordSalt)
        bytes.append(metadata.wrapNonce)
        bytes.append(metadata.wrappedVaultKey)
        bytes.append(metadata.wrapTag)
        return bytes
    }

    public static func decode(_ bytes: Data) throws -> VaultMetadata {
        guard bytes.count == encodedLength else {
            throw VaultMetadataError.invalidLength
        }
        guard bytes.prefix(4) == Data("PVLT".utf8) else {
            throw VaultMetadataError.invalidMagic
        }
        guard bytes[4] == 0x01 else {
            throw VaultMetadataError.unsupportedVersion
        }
        guard bytes[21] == 0x01, bytes[22] == 0x01 else {
            throw VaultMetadataError.unsupportedAlgorithm
        }
        guard bytes[23] == 0x00 else {
            throw VaultMetadataError.invalidFlags
        }
        guard bytes[33] == 0x00, bytes[34] == 0x00, bytes[35] == 0x00 else {
            throw VaultMetadataError.invalidReservedBytes
        }

        return VaultMetadata(
            vaultID: bytes[5..<21],
            memoryKiB: readUInt32(from: bytes, at: 24),
            iterations: readUInt32(from: bytes, at: 28),
            parallelism: bytes[32],
            passwordSalt: bytes[36..<52],
            wrapNonce: bytes[52..<64],
            wrappedVaultKey: bytes[64..<96],
            wrapTag: bytes[96..<112]
        )
    }

    public static func authenticatedHeader(for metadata: VaultMetadata) throws -> Data {
        Data(try encode(metadata).prefix(52))
    }

    private static func appendBigEndian(_ value: UInt32, to bytes: inout Data) {
        var bigEndianValue = value.bigEndian
        withUnsafeBytes(of: &bigEndianValue) { bytes.append(contentsOf: $0) }
    }

    private static func readUInt32(from bytes: Data, at offset: Int) -> UInt32 {
        bytes[offset..<(offset + 4)].reduce(UInt32.zero) { partial, byte in
            (partial << 8) | UInt32(byte)
        }
    }
}
