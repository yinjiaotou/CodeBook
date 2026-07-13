import Foundation
import Testing
@testable import PwdlockCore

@Test("SQLCipher database accepts a raw 32-byte vault key and persists encrypted rows")
func persistsRowsWithRawVaultKey() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let database = try EncryptedDatabase.open(
        at: directory.appendingPathComponent("vault.db"),
        vaultKey: Data(repeating: 0x42, count: 32)
    )
    defer { database.close() }

    try database.execute("CREATE TABLE login_items (title TEXT NOT NULL)")
    try database.execute("INSERT INTO login_items (title) VALUES ('Example')")

    #expect(try database.scalarInt("SELECT COUNT(*) FROM login_items") == 1)
}
