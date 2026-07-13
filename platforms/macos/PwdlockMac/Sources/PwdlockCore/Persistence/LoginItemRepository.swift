import CSQLCipher
import Foundation

public enum LoginItemRepositoryError: Error, Equatable {
    case database(Int32)
    case itemNotFound
}

public struct LoginItemRepository: Sendable {
    private let database: EncryptedDatabase

    public init(database: EncryptedDatabase) {
        self.database = database
    }

    public func migrate() throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS login_items (
            id TEXT PRIMARY KEY NOT NULL,
            title TEXT NOT NULL,
            payload BLOB NOT NULL
        )
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

    public func update(_ item: LoginItem) throws {
        let payload = try JSONEncoder().encode(item)
        try database.withHandle { handle in
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
            guard titleStatus == SQLITE_OK else { throw LoginItemRepositoryError.database(titleStatus) }
            guard payloadStatus == SQLITE_OK else { throw LoginItemRepositoryError.database(payloadStatus) }
            guard idStatus == SQLITE_OK else { throw LoginItemRepositoryError.database(idStatus) }

            let stepStatus = sqlite3_step(statement)
            guard stepStatus == SQLITE_DONE else { throw LoginItemRepositoryError.database(stepStatus) }
            guard sqlite3_changes(handle) == 1 else { throw LoginItemRepositoryError.itemNotFound }
        }
    }

    public func item(id: UUID) throws -> LoginItem? {
        try database.withHandle { handle in
            let statement = try prepare("SELECT payload FROM login_items WHERE id = ?", on: handle)
            defer { sqlite3_finalize(statement) }

            let bindStatus = id.uuidString.withCString {
                sqlite3_bind_text(statement, 1, $0, -1, sqliteTransient)
            }
            guard bindStatus == SQLITE_OK else { throw LoginItemRepositoryError.database(bindStatus) }

            let stepStatus = sqlite3_step(statement)
            guard stepStatus == SQLITE_ROW else {
                if stepStatus == SQLITE_DONE { return nil }
                throw LoginItemRepositoryError.database(stepStatus)
            }
            guard let pointer = sqlite3_column_blob(statement, 0) else {
                throw LoginItemRepositoryError.database(SQLITE_CORRUPT)
            }
            let count = Int(sqlite3_column_bytes(statement, 0))
            return try JSONDecoder().decode(LoginItem.self, from: Data(bytes: pointer, count: count))
        }
    }

    public func search(query: String) throws -> [LoginItem] {
        try database.withHandle { handle in
            let statement = try prepare(
                "SELECT payload FROM login_items WHERE title LIKE ? COLLATE NOCASE ORDER BY title ASC",
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
                guard let pointer = sqlite3_column_blob(statement, 0) else {
                    throw LoginItemRepositoryError.database(SQLITE_CORRUPT)
                }
                let count = Int(sqlite3_column_bytes(statement, 0))
                results.append(try JSONDecoder().decode(LoginItem.self, from: Data(bytes: pointer, count: count)))
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

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
