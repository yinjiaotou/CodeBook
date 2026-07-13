import CSQLCipher
import Foundation

public enum EncryptedDatabaseError: Error, Equatable {
    case invalidVaultKey
    case openFailed(Int32)
    case keyingFailed(Int32)
    case executionFailed(Int32)
    case backupFailed(Int32)
    case closed
}

public final class EncryptedDatabase: @unchecked Sendable {
    private var handle: OpaquePointer?

    private init(handle: OpaquePointer) {
        self.handle = handle
    }

    deinit {
        close()
    }

    public static func open(at url: URL, vaultKey: Data) throws -> EncryptedDatabase {
        guard vaultKey.count == 32 else {
            throw EncryptedDatabaseError.invalidVaultKey
        }

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let openStatus = url.path.withCString { path in
            sqlite3_open_v2(path, &handle, flags, nil)
        }
        guard openStatus == SQLITE_OK, let handle else {
            if let handle { sqlite3_close_v2(handle) }
            throw EncryptedDatabaseError.openFailed(openStatus)
        }

        let keyStatus = vaultKey.withUnsafeBytes { keyBuffer in
            sqlite3_key_v2(handle, "main", keyBuffer.baseAddress, Int32(keyBuffer.count))
        }
        guard keyStatus == SQLITE_OK else {
            sqlite3_close_v2(handle)
            throw EncryptedDatabaseError.keyingFailed(keyStatus)
        }

        let database = EncryptedDatabase(handle: handle)
        do {
            _ = try database.scalarInt("SELECT COUNT(*) FROM sqlite_master")
            return database
        } catch {
            database.close()
            throw error
        }
    }

    public func execute(_ sql: String) throws {
        let handle = try openHandle()
        let status = sql.withCString { sqlite3_exec(handle, $0, nil, nil, nil) }
        guard status == SQLITE_OK else {
            throw EncryptedDatabaseError.executionFailed(status)
        }
    }

    public func scalarInt(_ sql: String) throws -> Int64 {
        let handle = try openHandle()
        var statement: OpaquePointer?
        let prepareStatus = sql.withCString { sqlite3_prepare_v2(handle, $0, -1, &statement, nil) }
        guard prepareStatus == SQLITE_OK, let statement else {
            throw EncryptedDatabaseError.executionFailed(prepareStatus)
        }
        defer { sqlite3_finalize(statement) }

        let stepStatus = sqlite3_step(statement)
        guard stepStatus == SQLITE_ROW else {
            throw EncryptedDatabaseError.executionFailed(stepStatus)
        }
        return sqlite3_column_int64(statement, 0)
    }

    public func scalarText(_ sql: String) throws -> String {
        let handle = try openHandle()
        var statement: OpaquePointer?
        let prepareStatus = sql.withCString { sqlite3_prepare_v2(handle, $0, -1, &statement, nil) }
        guard prepareStatus == SQLITE_OK, let statement else {
            throw EncryptedDatabaseError.executionFailed(prepareStatus)
        }
        defer { sqlite3_finalize(statement) }

        let stepStatus = sqlite3_step(statement)
        guard stepStatus == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else {
            throw EncryptedDatabaseError.executionFailed(stepStatus)
        }
        return String(cString: text)
    }

    public func close() {
        guard let handle else { return }
        self.handle = nil
        sqlite3_close_v2(handle)
    }

    /// Creates a SQLCipher-to-SQLCipher snapshot. The destination is keyed before
    /// SQLite writes any database pages, so this never creates a plaintext copy.
    func createEncryptedBackup(at destinationURL: URL, vaultKey: Data) throws {
        let sourceHandle = try openHandle()
        let destination = try EncryptedDatabase.open(at: destinationURL, vaultKey: vaultKey)
        defer { destination.close() }

        let backup = try destination.withHandle { destinationHandle -> OpaquePointer in
            guard let backup = sqlite3_backup_init(destinationHandle, "main", sourceHandle, "main") else {
                throw EncryptedDatabaseError.backupFailed(sqlite3_errcode(destinationHandle))
            }
            return backup
        }

        let stepStatus = sqlite3_backup_step(backup, -1)
        let finishStatus = sqlite3_backup_finish(backup)
        guard stepStatus == SQLITE_DONE else {
            throw EncryptedDatabaseError.backupFailed(stepStatus)
        }
        guard finishStatus == SQLITE_OK else {
            throw EncryptedDatabaseError.backupFailed(finishStatus)
        }
    }

    private func openHandle() throws -> OpaquePointer {
        guard let handle else {
            throw EncryptedDatabaseError.closed
        }
        return handle
    }

    func withHandle<T>(_ operation: (OpaquePointer) throws -> T) throws -> T {
        try operation(openHandle())
    }
}
