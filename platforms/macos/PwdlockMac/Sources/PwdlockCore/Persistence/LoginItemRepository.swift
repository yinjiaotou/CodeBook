import CSQLCipher
import Foundation

public enum LoginItemRepositoryError: Error, Equatable {
    case database(Int32)
    case itemNotFound
    case conflictChanged
}

public struct LoginItemRepository: Sendable {
    private let database: EncryptedDatabase

    public init(database: EncryptedDatabase) {
        self.database = database
    }

    public func migrate() throws {
        try database.execute("PRAGMA foreign_keys = ON")
        try database.execute("""
        CREATE TABLE IF NOT EXISTS login_items (
            id TEXT PRIMARY KEY NOT NULL,
            title TEXT NOT NULL,
            payload BLOB NOT NULL
        )
        """)
        try database.execute("""
        CREATE TABLE IF NOT EXISTS conflict_groups (
            id TEXT PRIMARY KEY NOT NULL,
            record_id TEXT NOT NULL,
            title TEXT NOT NULL,
            created_at_ms INTEGER NOT NULL,
            state TEXT NOT NULL CHECK(state = 'pending')
        )
        """)
        try database.execute("""
        CREATE TABLE IF NOT EXISTS conflict_variants (
            id TEXT PRIMARY KEY NOT NULL,
            group_id TEXT NOT NULL REFERENCES conflict_groups(id) ON DELETE CASCADE,
            kind TEXT NOT NULL CHECK(kind IN ('local', 'imported')),
            source_vault_id TEXT NOT NULL,
            payload BLOB NOT NULL,
            UNIQUE(group_id, kind)
        )
        """)
        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_conflict_groups_record
        ON conflict_groups(record_id, state)
        """)
    }

    public func create(_ item: LoginItem) throws {
        try database.withHandle { handle in
            try insert(item, on: handle)
        }
    }

    /// Inserts an imported archive as one all-or-nothing database transaction.
    public func createAll(_ items: [LoginItem]) throws {
        try database.withHandle { handle in
            let beginStatus = "BEGIN IMMEDIATE TRANSACTION".withCString { sqlite3_exec(handle, $0, nil, nil, nil) }
            guard beginStatus == SQLITE_OK else { throw LoginItemRepositoryError.database(beginStatus) }
            var committed = false
            defer {
                if !committed {
                    _ = "ROLLBACK".withCString { sqlite3_exec(handle, $0, nil, nil, nil) }
                }
            }

            for item in items {
                try insert(item, on: handle)
            }

            let commitStatus = "COMMIT".withCString { sqlite3_exec(handle, $0, nil, nil, nil) }
            guard commitStatus == SQLITE_OK else { throw LoginItemRepositoryError.database(commitStatus) }
            committed = true
        }
    }

    public func mergeImportedItems(
        _ items: [LoginItem],
        importedSourceVaultID: UUID,
        localSourceVaultID: UUID,
        now: Date = Date()
    ) throws -> ImportMergeSummary {
        try mergeImportedItems(
            items,
            importedSourceVaultID: importedSourceVaultID,
            localSourceVaultID: localSourceVaultID,
            now: now,
            beforeCommit: {}
        )
    }

    func mergeImportedItems(
        _ items: [LoginItem],
        importedSourceVaultID: UUID,
        localSourceVaultID: UUID,
        now: Date = Date(),
        beforeCommit: () throws -> Void
    ) throws -> ImportMergeSummary {
        try database.withHandle { handle in
            try beginTransaction(on: handle)
            var committed = false
            defer {
                if !committed {
                    _ = "ROLLBACK".withCString { sqlite3_exec(handle, $0, nil, nil, nil) }
                }
            }

            var added = 0
            var identical = 0
            var conflicts = 0
            for imported in items {
                guard let local = try item(id: imported.id, on: handle) else {
                    try insert(imported, on: handle)
                    added += 1
                    continue
                }
                guard !logicallyEquivalent(local, imported) else {
                    identical += 1
                    continue
                }

                let localPayload = try conflictPayloadEncoder.encode(local)
                let importedPayload = try conflictPayloadEncoder.encode(imported)
                guard try !equivalentConflictExists(
                    recordID: imported.id,
                    importedSourceVaultID: importedSourceVaultID,
                    localPayload: localPayload,
                    importedPayload: importedPayload,
                    on: handle
                ) else {
                    continue
                }
                let groupID = UUID()
                try insertConflictGroup(
                    id: groupID,
                    recordID: imported.id,
                    title: local.title,
                    createdAt: now,
                    on: handle
                )
                try insertConflictVariant(
                    groupID: groupID,
                    kind: .local,
                    sourceVaultID: localSourceVaultID,
                    payload: localPayload,
                    on: handle
                )
                try insertConflictVariant(
                    groupID: groupID,
                    kind: .imported,
                    sourceVaultID: importedSourceVaultID,
                    payload: importedPayload,
                    on: handle
                )
                conflicts += 1
            }

            try beforeCommit()
            try commitTransaction(on: handle)
            committed = true
            return ImportMergeSummary(added: added, identical: identical, conflicts: conflicts)
        }
    }

    public func pendingConflicts() throws -> [ImportConflict] {
        try database.withHandle { handle in
            let statement = try prepare(
                """
                SELECT g.id, g.record_id, g.title, g.created_at_ms,
                       v.id, v.kind, v.source_vault_id, v.payload
                FROM conflict_groups g
                JOIN conflict_variants v ON v.group_id = g.id
                WHERE g.state = 'pending'
                ORDER BY g.created_at_ms ASC, g.id ASC, v.kind ASC
                """,
                on: handle
            )
            defer { sqlite3_finalize(statement) }

            struct PartialConflict {
                let id: UUID
                let recordID: UUID
                let title: String
                let createdAt: Date
                var local: ConflictVariant?
                var imported: ConflictVariant?
            }
            var order: [UUID] = []
            var partials: [UUID: PartialConflict] = [:]

            while true {
                let status = sqlite3_step(statement)
                if status == SQLITE_DONE { break }
                guard status == SQLITE_ROW,
                      let groupID = uuidColumn(statement, index: 0),
                      let recordID = uuidColumn(statement, index: 1),
                      let title = textColumn(statement, index: 2),
                      let variantID = uuidColumn(statement, index: 4),
                      let kindText = textColumn(statement, index: 5),
                      let kind = ConflictVariantKind(rawValue: kindText),
                      let sourceVaultID = uuidColumn(statement, index: 6),
                      let payload = blobColumn(statement, index: 7) else {
                    throw LoginItemRepositoryError.database(status == SQLITE_ROW ? SQLITE_CORRUPT : status)
                }
                let item = try JSONDecoder().decode(LoginItem.self, from: payload)
                guard item.id == recordID,
                      partials[groupID] == nil || partials[groupID]?.recordID == recordID else {
                    throw LoginItemRepositoryError.database(SQLITE_CORRUPT)
                }
                let variant = ConflictVariant(id: variantID, kind: kind, sourceVaultID: sourceVaultID, item: item)
                var partial = partials[groupID] ?? PartialConflict(
                    id: groupID,
                    recordID: recordID,
                    title: title,
                    createdAt: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 3)) / 1_000),
                    local: nil,
                    imported: nil
                )
                if partials[groupID] == nil { order.append(groupID) }
                switch kind {
                case .local: partial.local = variant
                case .imported: partial.imported = variant
                }
                partials[groupID] = partial
            }

            return try order.map { id in
                guard let partial = partials[id],
                      let local = partial.local,
                      let imported = partial.imported else {
                    throw LoginItemRepositoryError.database(SQLITE_CORRUPT)
                }
                return ImportConflict(
                    id: partial.id,
                    recordID: partial.recordID,
                    title: partial.title,
                    createdAt: partial.createdAt,
                    local: local,
                    imported: imported
                )
            }
        }
    }

    public func pendingConflictCount() throws -> Int {
        Int(try database.scalarInt("SELECT COUNT(*) FROM conflict_groups WHERE state = 'pending'"))
    }

    public func resolveKeepingLocal(conflictID: UUID) throws {
        try database.withHandle { handle in
            try withTransaction(on: handle) {
                _ = try loadConflict(id: conflictID, on: handle)
                try deleteConflict(id: conflictID, on: handle)
            }
        }
    }

    public func resolveUsingImported(conflictID: UUID) throws {
        let conflictWasRebased = try database.withHandle { handle in
            try withTransaction(on: handle) { () -> Bool in
                let conflict = try loadConflict(id: conflictID, on: handle)
                guard let current = try item(id: conflict.recordID, on: handle) else {
                    throw LoginItemRepositoryError.itemNotFound
                }
                guard logicallyEquivalent(current, conflict.local.item) else {
                    try rebaseLocalVariant(current, conflict: conflict, on: handle)
                    return true
                }
                try update(conflict.imported.item, on: handle)
                try deleteConflict(id: conflictID, on: handle)
                return false
            }
        }
        if conflictWasRebased {
            throw LoginItemRepositoryError.conflictChanged
        }
    }

    public func resolveManually(
        conflictID: UUID,
        merge: ManualLoginMerge,
        now: Date = Date()
    ) throws {
        let conflictWasRebased = try database.withHandle { handle in
            try withTransaction(on: handle) { () -> Bool in
                let conflict = try loadConflict(id: conflictID, on: handle)
                guard let current = try item(id: conflict.recordID, on: handle) else {
                    throw LoginItemRepositoryError.itemNotFound
                }
                guard logicallyEquivalent(current, conflict.local.item) else {
                    try rebaseLocalVariant(current, conflict: conflict, on: handle)
                    return true
                }
                let local = conflict.local.item
                let imported = conflict.imported.item
                let highestRevision = max(local.revision, imported.revision)
                guard highestRevision < Int.max else {
                    throw LoginItemRepositoryError.database(SQLITE_CONSTRAINT)
                }
                let merged = LoginItem(
                    id: local.id,
                    title: merge.title,
                    username: merge.username,
                    password: merge.password,
                    url: merge.url,
                    category: merge.category,
                    note: merge.note,
                    createdAt: local.createdAt,
                    updatedAt: now,
                    revision: highestRevision + 1,
                    deviceID: local.deviceID
                )
                try update(merged, on: handle)
                try deleteConflict(id: conflictID, on: handle)
                return false
            }
        }
        if conflictWasRebased {
            throw LoginItemRepositoryError.conflictChanged
        }
    }

    public func update(_ item: LoginItem) throws {
        try database.withHandle { handle in
            try update(item, on: handle)
        }
    }

    public func item(id: UUID) throws -> LoginItem? {
        try database.withHandle { handle in
            try item(id: id, on: handle)
        }
    }

    public func search(query: String) throws -> [LoginItem] {
        try database.withHandle { handle in
            let statement = try prepare(
                "SELECT id, payload FROM login_items WHERE title LIKE ? COLLATE NOCASE ORDER BY title ASC",
                on: handle
            )
            defer { sqlite3_finalize(statement) }

            let bindStatus = "%\(query)%".withCString {
                sqlite3_bind_text(statement, 1, $0, -1, sqliteTransient)
            }
            guard bindStatus == SQLITE_OK else { throw LoginItemRepositoryError.database(bindStatus) }

            var results: [LoginItem] = []
            while true {
                let stepStatus = sqlite3_step(statement)
                if stepStatus == SQLITE_DONE { return results }
                guard stepStatus == SQLITE_ROW else { throw LoginItemRepositoryError.database(stepStatus) }
                guard let storedID = uuidColumn(statement, index: 0),
                      let pointer = sqlite3_column_blob(statement, 1) else {
                    throw LoginItemRepositoryError.database(SQLITE_CORRUPT)
                }
                let count = Int(sqlite3_column_bytes(statement, 1))
                let item = try JSONDecoder().decode(LoginItem.self, from: Data(bytes: pointer, count: count))
                guard item.id == storedID else {
                    throw LoginItemRepositoryError.database(SQLITE_CORRUPT)
                }
                results.append(item)
            }
        }
    }

    public func delete(id: UUID) throws {
        try database.withHandle { handle in
            let statement = try prepare("DELETE FROM login_items WHERE id = ?", on: handle)
            defer { sqlite3_finalize(statement) }

            let bindStatus = id.uuidString.withCString {
                sqlite3_bind_text(statement, 1, $0, -1, sqliteTransient)
            }
            guard bindStatus == SQLITE_OK else { throw LoginItemRepositoryError.database(bindStatus) }

            let stepStatus = sqlite3_step(statement)
            guard stepStatus == SQLITE_DONE else { throw LoginItemRepositoryError.database(stepStatus) }
        }
    }

    private func prepare(_ sql: String, on handle: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let status = sql.withCString { sqlite3_prepare_v2(handle, $0, -1, &statement, nil) }
        guard status == SQLITE_OK, let statement else {
            throw LoginItemRepositoryError.database(status)
        }
        return statement
    }

    private func beginTransaction(on handle: OpaquePointer) throws {
        let status = "BEGIN IMMEDIATE TRANSACTION".withCString { sqlite3_exec(handle, $0, nil, nil, nil) }
        guard status == SQLITE_OK else { throw LoginItemRepositoryError.database(status) }
    }

    private func commitTransaction(on handle: OpaquePointer) throws {
        let status = "COMMIT".withCString { sqlite3_exec(handle, $0, nil, nil, nil) }
        guard status == SQLITE_OK else { throw LoginItemRepositoryError.database(status) }
    }

    private func withTransaction<T>(on handle: OpaquePointer, operation: () throws -> T) throws -> T {
        try beginTransaction(on: handle)
        var committed = false
        defer {
            if !committed {
                _ = "ROLLBACK".withCString { sqlite3_exec(handle, $0, nil, nil, nil) }
            }
        }
        let result = try operation()
        try commitTransaction(on: handle)
        committed = true
        return result
    }

    private func item(id: UUID, on handle: OpaquePointer) throws -> LoginItem? {
        let statement = try prepare("SELECT payload FROM login_items WHERE id = ?", on: handle)
        defer { sqlite3_finalize(statement) }
        let bindStatus = id.uuidString.withCString { sqlite3_bind_text(statement, 1, $0, -1, sqliteTransient) }
        guard bindStatus == SQLITE_OK else { throw LoginItemRepositoryError.database(bindStatus) }
        let status = sqlite3_step(statement)
        if status == SQLITE_DONE { return nil }
        guard status == SQLITE_ROW, let payload = blobColumn(statement, index: 0) else {
            throw LoginItemRepositoryError.database(status == SQLITE_ROW ? SQLITE_CORRUPT : status)
        }
        let decoded = try JSONDecoder().decode(LoginItem.self, from: payload)
        guard decoded.id == id else {
            throw LoginItemRepositoryError.database(SQLITE_CORRUPT)
        }
        return decoded
    }

    private func update(_ item: LoginItem, on handle: OpaquePointer) throws {
        let payload = try JSONEncoder().encode(item)
        let statement = try prepare(
            "UPDATE login_items SET title = ?, payload = ? WHERE id = ?",
            on: handle
        )
        defer { sqlite3_finalize(statement) }
        let titleStatus = item.title.withCString {
            sqlite3_bind_text(statement, 1, $0, -1, sqliteTransient)
        }
        let payloadStatus = payload.withUnsafeBytes {
            sqlite3_bind_blob(statement, 2, $0.baseAddress, Int32($0.count), sqliteTransient)
        }
        let idStatus = item.id.uuidString.withCString {
            sqlite3_bind_text(statement, 3, $0, -1, sqliteTransient)
        }
        for status in [titleStatus, payloadStatus, idStatus] {
            guard status == SQLITE_OK else { throw LoginItemRepositoryError.database(status) }
        }
        let stepStatus = sqlite3_step(statement)
        guard stepStatus == SQLITE_DONE else { throw LoginItemRepositoryError.database(stepStatus) }
        guard sqlite3_changes(handle) == 1 else { throw LoginItemRepositoryError.itemNotFound }
    }

    private func loadConflict(id: UUID, on handle: OpaquePointer) throws -> ImportConflict {
        let statement = try prepare(
            """
            SELECT g.record_id, g.title, g.created_at_ms,
                   v.id, v.kind, v.source_vault_id, v.payload
            FROM conflict_groups g
            JOIN conflict_variants v ON v.group_id = g.id
            WHERE g.id = ? AND g.state = 'pending'
            ORDER BY v.kind ASC
            """,
            on: handle
        )
        defer { sqlite3_finalize(statement) }
        let bindStatus = id.uuidString.withCString {
            sqlite3_bind_text(statement, 1, $0, -1, sqliteTransient)
        }
        guard bindStatus == SQLITE_OK else { throw LoginItemRepositoryError.database(bindStatus) }

        var recordID: UUID?
        var title: String?
        var createdAt: Date?
        var local: ConflictVariant?
        var imported: ConflictVariant?
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW,
                  let rowRecordID = uuidColumn(statement, index: 0),
                  let rowTitle = textColumn(statement, index: 1),
                  let variantID = uuidColumn(statement, index: 3),
                  let kindText = textColumn(statement, index: 4),
                  let kind = ConflictVariantKind(rawValue: kindText),
                  let sourceVaultID = uuidColumn(statement, index: 5),
                  let payload = blobColumn(statement, index: 6) else {
                throw LoginItemRepositoryError.database(status == SQLITE_ROW ? SQLITE_CORRUPT : status)
            }
            let item = try JSONDecoder().decode(LoginItem.self, from: payload)
            guard item.id == rowRecordID, recordID == nil || recordID == rowRecordID else {
                throw LoginItemRepositoryError.database(SQLITE_CORRUPT)
            }
            recordID = rowRecordID
            title = rowTitle
            createdAt = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 2)) / 1_000)
            let variant = ConflictVariant(id: variantID, kind: kind, sourceVaultID: sourceVaultID, item: item)
            switch kind {
            case .local:
                guard local == nil else { throw LoginItemRepositoryError.database(SQLITE_CORRUPT) }
                local = variant
            case .imported:
                guard imported == nil else { throw LoginItemRepositoryError.database(SQLITE_CORRUPT) }
                imported = variant
            }
        }
        guard let recordID, let title, let createdAt, let local, let imported else {
            throw LoginItemRepositoryError.itemNotFound
        }
        return ImportConflict(
            id: id,
            recordID: recordID,
            title: title,
            createdAt: createdAt,
            local: local,
            imported: imported
        )
    }

    private func deleteConflict(id: UUID, on handle: OpaquePointer) throws {
        let statement = try prepare("DELETE FROM conflict_groups WHERE id = ?", on: handle)
        defer { sqlite3_finalize(statement) }
        let bindStatus = id.uuidString.withCString {
            sqlite3_bind_text(statement, 1, $0, -1, sqliteTransient)
        }
        guard bindStatus == SQLITE_OK else { throw LoginItemRepositoryError.database(bindStatus) }
        let status = sqlite3_step(statement)
        guard status == SQLITE_DONE else { throw LoginItemRepositoryError.database(status) }
        guard sqlite3_changes(handle) == 1 else { throw LoginItemRepositoryError.itemNotFound }
    }

    private func rebaseLocalVariant(
        _ current: LoginItem,
        conflict: ImportConflict,
        on handle: OpaquePointer
    ) throws {
        let payload = try conflictPayloadEncoder.encode(current)
        let variantStatement = try prepare(
            "UPDATE conflict_variants SET payload = ? WHERE id = ? AND kind = 'local'",
            on: handle
        )
        defer { sqlite3_finalize(variantStatement) }
        let payloadStatus = payload.withUnsafeBytes {
            sqlite3_bind_blob(variantStatement, 1, $0.baseAddress, Int32($0.count), sqliteTransient)
        }
        let variantIDStatus = conflict.local.id.uuidString.withCString {
            sqlite3_bind_text(variantStatement, 2, $0, -1, sqliteTransient)
        }
        for status in [payloadStatus, variantIDStatus] {
            guard status == SQLITE_OK else { throw LoginItemRepositoryError.database(status) }
        }
        let variantStep = sqlite3_step(variantStatement)
        guard variantStep == SQLITE_DONE, sqlite3_changes(handle) == 1 else {
            throw LoginItemRepositoryError.database(variantStep == SQLITE_DONE ? SQLITE_CORRUPT : variantStep)
        }

        let groupStatement = try prepare(
            "UPDATE conflict_groups SET title = ? WHERE id = ? AND state = 'pending'",
            on: handle
        )
        defer { sqlite3_finalize(groupStatement) }
        let titleStatus = current.title.withCString {
            sqlite3_bind_text(groupStatement, 1, $0, -1, sqliteTransient)
        }
        let groupIDStatus = conflict.id.uuidString.withCString {
            sqlite3_bind_text(groupStatement, 2, $0, -1, sqliteTransient)
        }
        for status in [titleStatus, groupIDStatus] {
            guard status == SQLITE_OK else { throw LoginItemRepositoryError.database(status) }
        }
        let groupStep = sqlite3_step(groupStatement)
        guard groupStep == SQLITE_DONE, sqlite3_changes(handle) == 1 else {
            throw LoginItemRepositoryError.database(groupStep == SQLITE_DONE ? SQLITE_CORRUPT : groupStep)
        }
    }

    private func equivalentConflictExists(
        recordID: UUID,
        importedSourceVaultID: UUID,
        localPayload: Data,
        importedPayload: Data,
        on handle: OpaquePointer
    ) throws -> Bool {
        let statement = try prepare(
            """
            SELECT 1
            FROM conflict_groups g
            JOIN conflict_variants local ON local.group_id = g.id AND local.kind = 'local'
            JOIN conflict_variants imported ON imported.group_id = g.id AND imported.kind = 'imported'
            WHERE g.record_id = ? AND g.state = 'pending'
              AND imported.source_vault_id = ?
              AND local.payload = ? AND imported.payload = ?
            LIMIT 1
            """,
            on: handle
        )
        defer { sqlite3_finalize(statement) }
        let recordStatus = recordID.uuidString.withCString { sqlite3_bind_text(statement, 1, $0, -1, sqliteTransient) }
        let sourceStatus = importedSourceVaultID.uuidString.withCString { sqlite3_bind_text(statement, 2, $0, -1, sqliteTransient) }
        let localStatus = localPayload.withUnsafeBytes { sqlite3_bind_blob(statement, 3, $0.baseAddress, Int32($0.count), sqliteTransient) }
        let importedStatus = importedPayload.withUnsafeBytes { sqlite3_bind_blob(statement, 4, $0.baseAddress, Int32($0.count), sqliteTransient) }
        for status in [recordStatus, sourceStatus, localStatus, importedStatus] {
            guard status == SQLITE_OK else { throw LoginItemRepositoryError.database(status) }
        }
        let status = sqlite3_step(statement)
        if status == SQLITE_ROW { return true }
        if status == SQLITE_DONE { return false }
        throw LoginItemRepositoryError.database(status)
    }

    private func logicallyEquivalent(_ local: LoginItem, _ imported: LoginItem) -> Bool {
        local.id == imported.id
            && local.title == imported.title
            && local.username == imported.username
            && local.password == imported.password
            && local.url == imported.url
            && local.category == imported.category
            && local.note == imported.note
            && protocolMilliseconds(local.createdAt) == protocolMilliseconds(imported.createdAt)
            && protocolMilliseconds(local.updatedAt) == protocolMilliseconds(imported.updatedAt)
            && local.revision == imported.revision
            && local.deviceID == imported.deviceID
    }

    private func protocolMilliseconds(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1_000)
    }

    private func insertConflictGroup(
        id: UUID,
        recordID: UUID,
        title: String,
        createdAt: Date,
        on handle: OpaquePointer
    ) throws {
        let statement = try prepare(
            "INSERT INTO conflict_groups (id, record_id, title, created_at_ms, state) VALUES (?, ?, ?, ?, 'pending')",
            on: handle
        )
        defer { sqlite3_finalize(statement) }
        let idStatus = id.uuidString.withCString { sqlite3_bind_text(statement, 1, $0, -1, sqliteTransient) }
        let recordStatus = recordID.uuidString.withCString { sqlite3_bind_text(statement, 2, $0, -1, sqliteTransient) }
        let titleStatus = title.withCString { sqlite3_bind_text(statement, 3, $0, -1, sqliteTransient) }
        let timeStatus = sqlite3_bind_int64(statement, 4, Int64(createdAt.timeIntervalSince1970 * 1_000))
        for status in [idStatus, recordStatus, titleStatus, timeStatus] {
            guard status == SQLITE_OK else { throw LoginItemRepositoryError.database(status) }
        }
        let status = sqlite3_step(statement)
        guard status == SQLITE_DONE else { throw LoginItemRepositoryError.database(status) }
    }

    private func insertConflictVariant(
        groupID: UUID,
        kind: ConflictVariantKind,
        sourceVaultID: UUID,
        payload: Data,
        on handle: OpaquePointer
    ) throws {
        let statement = try prepare(
            "INSERT INTO conflict_variants (id, group_id, kind, source_vault_id, payload) VALUES (?, ?, ?, ?, ?)",
            on: handle
        )
        defer { sqlite3_finalize(statement) }
        let idStatus = UUID().uuidString.withCString { sqlite3_bind_text(statement, 1, $0, -1, sqliteTransient) }
        let groupStatus = groupID.uuidString.withCString { sqlite3_bind_text(statement, 2, $0, -1, sqliteTransient) }
        let kindStatus = kind.rawValue.withCString { sqlite3_bind_text(statement, 3, $0, -1, sqliteTransient) }
        let sourceStatus = sourceVaultID.uuidString.withCString { sqlite3_bind_text(statement, 4, $0, -1, sqliteTransient) }
        let payloadStatus = payload.withUnsafeBytes { sqlite3_bind_blob(statement, 5, $0.baseAddress, Int32($0.count), sqliteTransient) }
        for status in [idStatus, groupStatus, kindStatus, sourceStatus, payloadStatus] {
            guard status == SQLITE_OK else { throw LoginItemRepositoryError.database(status) }
        }
        let status = sqlite3_step(statement)
        guard status == SQLITE_DONE else { throw LoginItemRepositoryError.database(status) }
    }

    private func insert(_ item: LoginItem, on handle: OpaquePointer) throws {
        let payload = try JSONEncoder().encode(item)
        let statement = try prepare(
            "INSERT INTO login_items (id, title, payload) VALUES (?, ?, ?)",
            on: handle
        )
        defer { sqlite3_finalize(statement) }

        let idStatus = item.id.uuidString.withCString {
            sqlite3_bind_text(statement, 1, $0, -1, sqliteTransient)
        }
        let titleStatus = item.title.withCString {
            sqlite3_bind_text(statement, 2, $0, -1, sqliteTransient)
        }
        let payloadStatus = payload.withUnsafeBytes {
            sqlite3_bind_blob(statement, 3, $0.baseAddress, Int32($0.count), sqliteTransient)
        }
        guard idStatus == SQLITE_OK else { throw LoginItemRepositoryError.database(idStatus) }
        guard titleStatus == SQLITE_OK else { throw LoginItemRepositoryError.database(titleStatus) }
        guard payloadStatus == SQLITE_OK else { throw LoginItemRepositoryError.database(payloadStatus) }

        let stepStatus = sqlite3_step(statement)
        guard stepStatus == SQLITE_DONE else { throw LoginItemRepositoryError.database(stepStatus) }
    }
}

private func textColumn(_ statement: OpaquePointer, index: Int32) -> String? {
    guard let pointer = sqlite3_column_text(statement, index) else { return nil }
    return String(cString: pointer)
}

private func uuidColumn(_ statement: OpaquePointer, index: Int32) -> UUID? {
    textColumn(statement, index: index).flatMap(UUID.init(uuidString:))
}

private func blobColumn(_ statement: OpaquePointer, index: Int32) -> Data? {
    let count = Int(sqlite3_column_bytes(statement, index))
    guard count >= 0 else { return nil }
    if count == 0 { return Data() }
    guard let pointer = sqlite3_column_blob(statement, index) else { return nil }
    return Data(bytes: pointer, count: count)
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
private let conflictPayloadEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
}()
