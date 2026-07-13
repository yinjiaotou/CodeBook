import Foundation
import Testing
@testable import PwdlockCore

@Test("login item repository saves and reads an item from SQLCipher")
func savesAndReadsLoginItem() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let database = try EncryptedDatabase.open(
        at: directory.appendingPathComponent("vault.db"),
        vaultKey: Data(repeating: 0x42, count: 32)
    )
    defer { database.close() }
    let repository = LoginItemRepository(database: database)
    let item = LoginItem(
        id: UUID(uuidString: "12345678-1234-1234-1234-123456789abc")!,
        title: "Example",
        username: "name@example.com",
        password: "not-logged",
        url: "https://example.com",
        category: "工作",
        note: "测试记录",
        createdAt: Date(timeIntervalSince1970: 1_760_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_760_000_001),
        revision: 1,
        deviceID: UUID(uuidString: "abcdefab-cdef-cdef-cdef-abcdefabcdef")!
    )

    try repository.migrate()
    try repository.create(item)

    #expect(try repository.item(id: item.id) == item)
}

@Test("login item repository searches titles inside SQLCipher")
func searchesLoginItemTitles() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let database = try EncryptedDatabase.open(
        at: directory.appendingPathComponent("vault.db"),
        vaultKey: Data(repeating: 0x42, count: 32)
    )
    defer { database.close() }
    let repository = LoginItemRepository(database: database)
    let matching = makeLoginItem(title: "GitHub")
    let other = makeLoginItem(title: "Notion", id: UUID(uuidString: "bbbbbbbb-1234-1234-1234-123456789abc")!)

    try repository.migrate()
    try repository.create(matching)
    try repository.create(other)

    #expect(try repository.search(query: "git") == [matching])
}

@Test("login item repository updates searchable title and encrypted payload")
func updatesLoginItem() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let database = try EncryptedDatabase.open(
        at: directory.appendingPathComponent("vault.db"),
        vaultKey: Data(repeating: 0x42, count: 32)
    )
    defer { database.close() }
    let repository = LoginItemRepository(database: database)
    let original = makeLoginItem(title: "Old title")
    let updated = LoginItem(
        id: original.id,
        title: "New title",
        username: "new@example.com",
        password: "new-secret",
        url: "https://new.example.com",
        category: "Personal",
        note: "Updated note",
        createdAt: original.createdAt,
        updatedAt: original.updatedAt.addingTimeInterval(1),
        revision: original.revision + 1,
        deviceID: original.deviceID
    )

    try repository.migrate()
    try repository.create(original)
    try repository.update(updated)

    #expect(try repository.item(id: original.id) == updated)
    #expect(try repository.search(query: "Old title").isEmpty)
    #expect(try repository.search(query: "New title") == [updated])
}

@Test("login item repository refuses updates for missing identifiers")
func rejectsMissingLoginItemUpdate() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let database = try EncryptedDatabase.open(
        at: directory.appendingPathComponent("vault.db"),
        vaultKey: Data(repeating: 0x42, count: 32)
    )
    defer { database.close() }
    let repository = LoginItemRepository(database: database)
    let missing = makeLoginItem(title: "Missing")

    try repository.migrate()

    #expect(throws: LoginItemRepositoryError.itemNotFound) {
        try repository.update(missing)
    }
    #expect(try repository.item(id: missing.id) == nil)
}

@Test("login item repository deletes an item by identifier")
func deletesLoginItem() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let database = try EncryptedDatabase.open(
        at: directory.appendingPathComponent("vault.db"),
        vaultKey: Data(repeating: 0x42, count: 32)
    )
    defer { database.close() }
    let repository = LoginItemRepository(database: database)
    let item = makeLoginItem(title: "Example")

    try repository.migrate()
    try repository.create(item)
    try repository.delete(id: item.id)

    #expect(try repository.item(id: item.id) == nil)
}

private func makeLoginItem(title: String, id: UUID = UUID(uuidString: "12345678-1234-1234-1234-123456789abc")!) -> LoginItem {
    LoginItem(
        id: id,
        title: title,
        username: "name@example.com",
        password: "not-logged",
        url: "https://example.com",
        category: "工作",
        note: "测试记录",
        createdAt: Date(timeIntervalSince1970: 1_760_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_760_000_001),
        revision: 1,
        deviceID: UUID(uuidString: "abcdefab-cdef-cdef-cdef-abcdefabcdef")!
    )
}
