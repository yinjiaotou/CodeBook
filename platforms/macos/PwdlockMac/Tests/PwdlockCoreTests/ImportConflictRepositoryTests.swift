import Foundation
import Dispatch
import Testing
@testable import PwdlockCore

@Test("import merge summary exposes added identical and conflict counts")
func importMergeSummaryContract() {
    let summary = ImportMergeSummary(added: 2, identical: 3, conflicts: 1)

    #expect(summary == ImportMergeSummary(added: 2, identical: 3, conflicts: 1))
}

@Test("manual merge input contains only editable business fields")
func manualMergeInputContract() {
    let input = ManualLoginMerge(
        title: "GitHub",
        username: "yin",
        password: "secret",
        url: "https://github.com",
        category: "工作",
        note: "主账号"
    )

    #expect(input.title == "GitHub")
    #expect(input.note == "主账号")
}

@Test("merge adds missing skips identical and preserves a differing local item")
func mergesArchiveRecordsAtomically() throws {
    let fixture = try ImportRepositoryFixture()
    defer { fixture.close() }
    let local = fixture.item(
        id: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!,
        title: "本地"
    )
    let identical = fixture.item(
        id: UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!,
        title: "相同"
    )
    let added = fixture.item(
        id: UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")!,
        title: "新增"
    )
    let importedConflict = fixture.copy(local, title: "导入")
    try fixture.repository.create(local)
    try fixture.repository.create(identical)

    let summary = try fixture.repository.mergeImportedItems(
        [identical, importedConflict, added],
        importedSourceVaultID: fixture.sourceVaultID,
        localSourceVaultID: fixture.localVaultID,
        now: Date(timeIntervalSince1970: 1_800_000_000)
    )

    #expect(summary == ImportMergeSummary(added: 1, identical: 1, conflicts: 1))
    #expect(try fixture.repository.item(id: local.id) == local)
    #expect(try fixture.repository.item(id: added.id) == added)
    let conflict = try #require(fixture.repository.pendingConflicts().first)
    #expect(conflict.local.item == local)
    #expect(conflict.imported.item == importedConflict)
    #expect(conflict.local.sourceVaultID == fixture.localVaultID)
    #expect(conflict.imported.sourceVaultID == fixture.sourceVaultID)
}

@Test("reimporting an equivalent conflict does not duplicate it")
func deduplicatesEquivalentPendingConflict() throws {
    let fixture = try ImportRepositoryFixture()
    defer { fixture.close() }
    let local = fixture.item(title: "本地")
    let imported = fixture.copy(local, title: "导入")
    try fixture.repository.create(local)

    _ = try fixture.repository.mergeImportedItems(
        [imported],
        importedSourceVaultID: fixture.sourceVaultID,
        localSourceVaultID: fixture.localVaultID
    )
    #expect(try fixture.database.scalarInt(
        "SELECT COUNT(*) FROM conflict_variants WHERE kind = 'imported' AND source_vault_id = '\(fixture.sourceVaultID.uuidString)'"
    ) == 1)
    let repeated = try fixture.repository.mergeImportedItems(
        [imported],
        importedSourceVaultID: fixture.sourceVaultID,
        localSourceVaultID: fixture.localVaultID
    )

    #expect(repeated == ImportMergeSummary(added: 0, identical: 0, conflicts: 0))
    #expect(try fixture.repository.pendingConflictCount() == 1)
}

@Test("records that differ only below protocol millisecond precision are identical")
func treatsSubmillisecondTimestampDifferencesAsIdentical() throws {
    let fixture = try ImportRepositoryFixture()
    defer { fixture.close() }
    let base = fixture.item(title: "同一记录")
    let local = LoginItem(
        id: base.id,
        title: base.title,
        username: base.username,
        password: base.password,
        url: base.url,
        category: base.category,
        note: base.note,
        createdAt: Date(timeIntervalSince1970: 1_760_000_000.123456),
        updatedAt: Date(timeIntervalSince1970: 1_760_000_001.987654),
        revision: base.revision,
        deviceID: base.deviceID
    )
    let imported = LoginItem(
        id: local.id,
        title: local.title,
        username: local.username,
        password: local.password,
        url: local.url,
        category: local.category,
        note: local.note,
        createdAt: Date(timeIntervalSince1970: 1_760_000_000.123),
        updatedAt: Date(timeIntervalSince1970: 1_760_000_001.987),
        revision: local.revision,
        deviceID: local.deviceID
    )
    try fixture.repository.create(local)

    let summary = try fixture.repository.mergeImportedItems(
        [imported],
        importedSourceVaultID: fixture.sourceVaultID,
        localSourceVaultID: fixture.localVaultID
    )

    #expect(summary == ImportMergeSummary(added: 0, identical: 1, conflicts: 0))
    #expect(try fixture.repository.pendingConflictCount() == 0)
    #expect(try fixture.repository.item(id: local.id) == local)
}

@Test("a failure before commit rolls back added records and conflicts")
func rollsBackEntireImportMerge() throws {
    struct SyntheticFailure: Error {}
    let fixture = try ImportRepositoryFixture()
    defer { fixture.close() }
    let local = fixture.item(title: "本地")
    let imported = fixture.copy(local, title: "导入")
    let added = fixture.item(title: "新增")
    try fixture.repository.create(local)

    #expect(throws: SyntheticFailure.self) {
        _ = try fixture.repository.mergeImportedItems(
            [imported, added],
            importedSourceVaultID: fixture.sourceVaultID,
            localSourceVaultID: fixture.localVaultID,
            beforeCommit: { throw SyntheticFailure() }
        )
    }

    #expect(try fixture.repository.item(id: added.id) == nil)
    #expect(try fixture.repository.pendingConflictCount() == 0)
}

@Test("merge rejects a database row whose embedded login ID mismatches its SQL key")
func rejectsMismatchedStoredLoginIdentifier() throws {
    let fixture = try ImportRepositoryFixture()
    defer { fixture.close() }
    let requestedID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    let wrongPayloadItem = fixture.item(
        id: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
        title: "损坏载荷"
    )
    let payload = try JSONEncoder().encode(wrongPayloadItem)
    let payloadHex = payload.map { String(format: "%02x", $0) }.joined()
    try fixture.database.execute(
        "INSERT INTO login_items (id, title, payload) VALUES ('\(requestedID.uuidString)', '损坏行', X'\(payloadHex)')"
    )
    let imported = fixture.item(id: requestedID, title: "导入记录")

    #expect(throws: LoginItemRepositoryError.self) {
        _ = try fixture.repository.item(id: requestedID)
    }
    #expect(throws: LoginItemRepositoryError.self) {
        _ = try fixture.repository.search(query: "损坏")
    }
    #expect(throws: LoginItemRepositoryError.self) {
        _ = try fixture.repository.mergeImportedItems(
            [imported],
            importedSourceVaultID: fixture.sourceVaultID,
            localSourceVaultID: fixture.localVaultID
        )
    }

    #expect(try fixture.repository.pendingConflictCount() == 0)
}

@Test("pending conflict decoding rejects a variant whose embedded ID mismatches the group")
func rejectsMismatchedConflictVariantIdentifier() throws {
    let fixture = try ImportRepositoryFixture()
    defer { fixture.close() }
    _ = try fixture.createConflict()
    let wrongItem = fixture.item(
        id: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
        title: "错误冲突变体"
    )
    let payload = try JSONEncoder().encode(wrongItem)
    let payloadHex = payload.map { String(format: "%02x", $0) }.joined()
    try fixture.database.execute(
        "UPDATE conflict_variants SET payload = X'\(payloadHex)' WHERE kind = 'imported'"
    )

    #expect(throws: LoginItemRepositoryError.self) {
        _ = try fixture.repository.pendingConflicts()
    }
}

@Test("database connection serializes another write across a rolling back merge transaction")
func serializesConnectionAcrossMergeTransaction() throws {
    struct SyntheticFailure: Error {}
    let fixture = try ImportRepositoryFixture()
    defer { fixture.close() }
    let local = fixture.item(title: "本地")
    let imported = fixture.copy(local, title: "导入")
    let concurrent = fixture.item(title: "并发新增")
    try fixture.repository.create(local)
    let repository = fixture.repository
    let sourceVaultID = fixture.sourceVaultID
    let localVaultID = fixture.localVaultID
    let transactionStarted = DispatchSemaphore(value: 0)
    let allowRollback = DispatchSemaphore(value: 0)
    let mergeFinished = DispatchSemaphore(value: 0)
    let concurrentWriteFinished = DispatchSemaphore(value: 0)

    DispatchQueue.global().async {
        _ = try? repository.mergeImportedItems(
            [imported],
            importedSourceVaultID: sourceVaultID,
            localSourceVaultID: localVaultID,
            beforeCommit: {
                transactionStarted.signal()
                allowRollback.wait()
                throw SyntheticFailure()
            }
        )
        mergeFinished.signal()
    }
    #expect(transactionStarted.wait(timeout: .now() + 2) == .success)

    DispatchQueue.global().async {
        try? repository.create(concurrent)
        concurrentWriteFinished.signal()
    }

    #expect(concurrentWriteFinished.wait(timeout: .now() + 0.2) == .timedOut)
    allowRollback.signal()
    #expect(mergeFinished.wait(timeout: .now() + 2) == .success)
    #expect(concurrentWriteFinished.wait(timeout: .now() + 2) == .success)
    #expect(try repository.item(id: concurrent.id) == concurrent)
    #expect(try repository.pendingConflictCount() == 0)
}

@Test("keeping local removes the conflict without changing the active record")
func resolvesConflictByKeepingLocal() throws {
    let fixture = try ImportRepositoryFixture()
    defer { fixture.close() }
    let (local, _, conflict) = try fixture.createConflict()

    try fixture.repository.resolveKeepingLocal(conflictID: conflict.id)

    #expect(try fixture.repository.item(id: local.id) == local)
    #expect(try fixture.repository.pendingConflictCount() == 0)
}

@Test("using imported replaces the active record and removes the conflict")
func resolvesConflictUsingImported() throws {
    let fixture = try ImportRepositoryFixture()
    defer { fixture.close() }
    let (local, imported, conflict) = try fixture.createConflict(importedRevision: 8)

    try fixture.repository.resolveUsingImported(conflictID: conflict.id)

    #expect(try fixture.repository.item(id: local.id) == imported)
    #expect(try fixture.repository.pendingConflictCount() == 0)
}

@Test("using imported refuses to overwrite a local record edited after conflict creation")
func rejectsStaleConflictUsingImported() throws {
    let fixture = try ImportRepositoryFixture()
    defer { fixture.close() }
    let (local, imported, conflict) = try fixture.createConflict(importedRevision: 8)
    let editedLocal = fixture.copy(local, title: "冲突后编辑", revision: local.revision + 1)
    try fixture.repository.update(editedLocal)

    #expect(throws: LoginItemRepositoryError.conflictChanged) {
        try fixture.repository.resolveUsingImported(conflictID: conflict.id)
    }

    #expect(try fixture.repository.item(id: local.id) == editedLocal)
    let refreshed = try #require(fixture.repository.pendingConflicts().first)
    #expect(refreshed.local.item == editedLocal)
    #expect(refreshed.imported.item == imported)
}

@Test("manual merge preserves local identity and advances the highest revision")
func resolvesConflictManually() throws {
    let fixture = try ImportRepositoryFixture()
    defer { fixture.close() }
    let (local, _, conflict) = try fixture.createConflict(importedRevision: 8)
    let now = Date(timeIntervalSince1970: 1_900_000_000)
    let merge = ManualLoginMerge(
        title: "合并标题",
        username: "merged-user",
        password: "merged-secret",
        url: "https://merged.example.com",
        category: "合并分类",
        note: "合并备注"
    )

    try fixture.repository.resolveManually(conflictID: conflict.id, merge: merge, now: now)

    let loaded = try fixture.repository.item(id: local.id)
    let result = try #require(loaded)
    #expect(result.id == local.id)
    #expect(result.createdAt == local.createdAt)
    #expect(result.deviceID == local.deviceID)
    #expect(result.updatedAt == now)
    #expect(result.revision == 9)
    #expect(result.title == merge.title)
    #expect(result.username == merge.username)
    #expect(result.password == merge.password)
    #expect(result.url == merge.url)
    #expect(result.category == merge.category)
    #expect(result.note == merge.note)
    #expect(try fixture.repository.pendingConflictCount() == 0)
}

@Test("manual merge refuses to overwrite a local record edited after conflict creation")
func rejectsStaleConflictManualMerge() throws {
    let fixture = try ImportRepositoryFixture()
    defer { fixture.close() }
    let (local, _, conflict) = try fixture.createConflict(importedRevision: 8)
    let editedLocal = fixture.copy(local, title: "冲突后编辑", revision: 20)
    try fixture.repository.update(editedLocal)
    let merge = ManualLoginMerge(
        title: "旧界面合并值",
        username: local.username,
        password: local.password,
        url: local.url,
        category: local.category,
        note: local.note
    )

    #expect(throws: LoginItemRepositoryError.conflictChanged) {
        try fixture.repository.resolveManually(conflictID: conflict.id, merge: merge)
    }

    #expect(try fixture.repository.item(id: local.id) == editedLocal)
    let refreshed = try #require(fixture.repository.pendingConflicts().first)
    #expect(refreshed.local.item == editedLocal)
}

private final class ImportRepositoryFixture {
    let sourceVaultID = UUID(uuidString: "dddddddd-dddd-4ddd-8ddd-dddddddddddd")!
    let localVaultID = UUID(uuidString: "ffffffff-ffff-4fff-8fff-ffffffffffff")!
    let directory: URL
    let database: EncryptedDatabase
    let repository: LoginItemRepository

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        database = try EncryptedDatabase.open(
            at: directory.appendingPathComponent("vault.db"),
            vaultKey: Data(repeating: 0x42, count: 32)
        )
        repository = LoginItemRepository(database: database)
        try repository.migrate()
    }

    func close() {
        database.close()
        try? FileManager.default.removeItem(at: directory)
    }

    func item(id: UUID = UUID(), title: String, revision: Int = 1) -> LoginItem {
        LoginItem(
            id: id,
            title: title,
            username: "name@example.com",
            password: "secret",
            url: "https://example.com",
            category: "工作",
            note: "测试记录",
            createdAt: Date(timeIntervalSince1970: 1_760_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_760_000_001),
            revision: revision,
            deviceID: UUID(uuidString: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee")!
        )
    }

    func copy(_ item: LoginItem, title: String, revision: Int? = nil) -> LoginItem {
        LoginItem(
            id: item.id,
            title: title,
            username: item.username,
            password: item.password,
            url: item.url,
            category: item.category,
            note: item.note,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            revision: revision ?? item.revision,
            deviceID: item.deviceID
        )
    }

    func createConflict(importedRevision: Int = 2) throws -> (LoginItem, LoginItem, ImportConflict) {
        let local = item(title: "本地", revision: 3)
        let imported = copy(local, title: "导入", revision: importedRevision)
        try repository.create(local)
        _ = try repository.mergeImportedItems(
            [imported],
            importedSourceVaultID: sourceVaultID,
            localSourceVaultID: localVaultID
        )
        return (local, imported, try #require(repository.pendingConflicts().first))
    }
}
