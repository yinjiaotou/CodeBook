import Foundation

public struct VaultMetadataStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func save(_ metadata: VaultMetadata) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let destination = directory.appendingPathComponent("vault.meta", isDirectory: false)
        let temporary = directory.appendingPathComponent(".vault.meta.\(UUID().uuidString)", isDirectory: false)
        defer { try? fileManager.removeItem(at: temporary) }

        let bytes = try VaultMetadataCodec.encode(metadata)
        try bytes.write(to: temporary, options: .withoutOverwriting)

        let handle = try FileHandle(forWritingTo: temporary)
        try handle.synchronize()
        try handle.close()

        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: destination)
        }
    }

    public func load() throws -> VaultMetadata {
        let bytes = try Data(contentsOf: directory.appendingPathComponent("vault.meta", isDirectory: false))
        return try VaultMetadataCodec.decode(bytes)
    }
}
