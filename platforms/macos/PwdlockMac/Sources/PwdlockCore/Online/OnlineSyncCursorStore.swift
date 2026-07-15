import Foundation

public enum OnlineSyncCursorStore {
    public static func cursor(in database: EncryptedDatabase, vaultID: UUID) throws -> String? {
        try database.execute("CREATE TABLE IF NOT EXISTS online_sync_state (vault_id TEXT PRIMARY KEY, cursor TEXT NOT NULL)")
        let escaped = vaultID.uuidString.lowercased().replacingOccurrences(of: "'", with: "''")
        do { return try database.scalarText("SELECT cursor FROM online_sync_state WHERE vault_id = '\(escaped)'") }
        catch { return nil }
    }

    public static func save(_ cursor: String, vaultID: UUID, in database: EncryptedDatabase) throws {
        try database.execute("CREATE TABLE IF NOT EXISTS online_sync_state (vault_id TEXT PRIMARY KEY, cursor TEXT NOT NULL)")
        let id = vaultID.uuidString.lowercased().replacingOccurrences(of: "'", with: "''")
        let value = cursor.replacingOccurrences(of: "'", with: "''")
        try database.execute("INSERT INTO online_sync_state (vault_id, cursor) VALUES ('\(id)', '\(value)') ON CONFLICT(vault_id) DO UPDATE SET cursor = excluded.cursor")
    }
}
