import Foundation
import Testing
@testable import PwdlockCore

@Test("v1 metadata encodes the fixed 112-byte layout")
func encodesV1Metadata() throws {
    let metadata = VaultMetadata(
        vaultID: Data(repeating: 0x11, count: 16),
        memoryKiB: 65_536,
        iterations: 3,
        parallelism: 1,
        passwordSalt: Data(repeating: 0x22, count: 16),
        wrapNonce: Data(repeating: 0x33, count: 12),
        wrappedVaultKey: Data(repeating: 0x44, count: 32),
        wrapTag: Data(repeating: 0x55, count: 16)
    )

    let bytes = try VaultMetadataCodec.encode(metadata)

    #expect(bytes.count == 112)
    #expect(bytes.prefix(4) == Data("PVLT".utf8))
    #expect(bytes[4] == 0x01)
    #expect(bytes[21] == 0x01)
    #expect(bytes[22] == 0x01)
    #expect(bytes[23] == 0x00)
    #expect(bytes[24..<28] == Data([0x00, 0x01, 0x00, 0x00]))
}

@Test("decoder rejects non-zero reserved flags")
func rejectsNonZeroFlags() throws {
    var bytes = try VaultMetadataCodec.encode(.fixture)
    bytes[23] = 0x01

    #expect(throws: VaultMetadataError.invalidFlags) {
        _ = try VaultMetadataCodec.decode(bytes)
    }
}

@Test("metadata store atomically persists and reloads a metadata record")
func persistsAndReloadsMetadata() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let metadata = VaultMetadata.fixture
    let store = VaultMetadataStore(directory: directory)

    try store.save(metadata)

    #expect(try store.load() == metadata)
}

extension VaultMetadata {
    static let fixture = VaultMetadata(
        vaultID: Data(repeating: 0x11, count: 16),
        memoryKiB: 65_536,
        iterations: 3,
        parallelism: 1,
        passwordSalt: Data(repeating: 0x22, count: 16),
        wrapNonce: Data(repeating: 0x33, count: 12),
        wrappedVaultKey: Data(repeating: 0x44, count: 32),
        wrapTag: Data(repeating: 0x55, count: 16)
    )
}
