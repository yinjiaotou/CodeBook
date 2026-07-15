import Foundation
import Darwin
@preconcurrency import LocalAuthentication

public enum VaultSessionError: Error, Equatable {
    case vaultAlreadyExists
    case alreadyUnlocked
    case locked
    case masterPasswordTooShort
    case backupNotFound
    case backupValidationFailed
    case backupFailed
    case restoreFailed
    case archiveExportFailed
    case archiveImportFailed
    case masterPasswordUnlockRequired
    case biometricSetupFailed
    case biometricUnlockFailed
    case biometricCleanupFailed
}

public enum VaultUnlockMethod: Equatable, Sendable {
    case masterPassword
    case biometric
}

public final class VaultSession {
    public typealias ArchiveDataReader = (FileHandle, Int) throws -> Data
    public typealias StagedVaultPublisher = (URL, URL) throws -> Void
    public typealias RandomBytes = (Int) throws -> Data

    public let directory: URL
    private let metadataStore: VaultMetadataStore
    private let archiveDataReader: ArchiveDataReader
    private let stagedVaultPublisher: StagedVaultPublisher
    private let biometricKeyStore: any BiometricKeyStoring
    private let randomBytes: RandomBytes
    private var database: EncryptedDatabase?
    private var vaultKey: Data?
    public private(set) var unlockMethod: VaultUnlockMethod?

    public init(
        directory: URL,
        archiveDataReader: ArchiveDataReader? = nil,
        stagedVaultPublisher: StagedVaultPublisher? = nil,
        biometricKeyStore: any BiometricKeyStoring = KeychainBiometricKeyStore(),
        randomBytes: @escaping RandomBytes = { try SecureRandom.bytes(count: $0) }
    ) {
        self.directory = directory
        self.metadataStore = VaultMetadataStore(directory: directory)
        self.archiveDataReader = archiveDataReader ?? { handle, verifiedSize in
            try VaultSession.readVerifiedArchive(from: handle, byteCount: verifiedSize)
        }
        self.stagedVaultPublisher = stagedVaultPublisher ?? { stagingURL, targetURL in
            try VaultSession.publishStagedVault(from: stagingURL, to: targetURL)
        }
        self.biometricKeyStore = biometricKeyStore
        self.randomBytes = randomBytes
    }

    deinit {
        lock()
    }

    public var isUnlocked: Bool {
        database != nil
    }

    public func create(masterPassword: String) throws {
        guard !isUnlocked else { throw VaultSessionError.alreadyUnlocked }
        guard MasterPasswordPolicy.isValid(masterPassword) else {
            throw VaultSessionError.masterPasswordTooShort
        }
        guard !localVaultExists() else {
            throw VaultSessionError.vaultAlreadyExists
        }

        let created = try VaultBootstrap.create(masterPassword: masterPassword)
        try metadataStore.save(created.metadata)
        database = try openDatabase(vaultKey: created.vaultKey)
        vaultKey = created.vaultKey
        unlockMethod = .masterPassword
    }

    public func unlock(masterPassword: String) throws {
        guard !isUnlocked else { throw VaultSessionError.alreadyUnlocked }

        let metadata = try metadataStore.load()
        let unlockedVaultKey = try VaultKeyEnvelope.unwrap(metadata, masterPassword: masterPassword)
        database = try openDatabase(vaultKey: unlockedVaultKey)
        vaultKey = unlockedVaultKey
        unlockMethod = .masterPassword
    }

    public func changeMasterPassword(currentPassword: String, newPassword: String) throws {
        guard isUnlocked else { throw VaultSessionError.locked }
        guard MasterPasswordPolicy.isValid(newPassword) else {
            throw VaultSessionError.masterPasswordTooShort
        }

        let currentMetadata = try metadataStore.load()
        let vaultKey = try VaultKeyEnvelope.unwrap(currentMetadata, masterPassword: currentPassword)
        let replacementMetadata = try VaultKeyEnvelope.wrap(
            vaultKey: vaultKey,
            masterPassword: newPassword,
            vaultID: currentMetadata.vaultID,
            passwordSalt: SecureRandom.bytes(count: 16),
            wrapNonce: SecureRandom.bytes(count: 12),
            parameters: Argon2idParameters(
                memoryKiB: currentMetadata.memoryKiB,
                iterations: currentMetadata.iterations,
                parallelism: UInt32(currentMetadata.parallelism)
            )
        )
        do {
            try disableBiometricUnlock()
        } catch {
            throw VaultSessionError.biometricCleanupFailed
        }
        try metadataStore.save(replacementMetadata)
    }

    public func lock() {
        database?.close()
        database = nil
        clearRetainedVaultKey()
        unlockMethod = nil
    }

    public var isBiometricUnlockConfigured: Bool {
        guard let vaultID = try? biometricVaultID() else { return false }
        return biometricKeyStore.contains(vaultID: vaultID)
            && FileManager.default.fileExists(atPath: biometricEnvelopeURL.path)
    }

    public func enableBiometricUnlock() throws {
        guard isUnlocked, unlockMethod == .masterPassword, let vaultKey else {
            throw VaultSessionError.masterPasswordUnlockRequired
        }
        let vaultID: UUID
        do {
            vaultID = try biometricVaultID()
        } catch {
            throw VaultSessionError.biometricSetupFailed
        }

        var wrappingKey: Data
        let nonce: Data
        do {
            wrappingKey = try randomBytes(32)
            nonce = try randomBytes(12)
        } catch {
            throw VaultSessionError.biometricSetupFailed
        }
        defer { wrappingKey.resetBytes(in: 0..<wrappingKey.count) }
        do {
            try biometricKeyStore.create(wrappingKey, vaultID: vaultID)
            let envelope = try BiometricVaultEnvelope.seal(
                vaultKey: vaultKey,
                wrappingKey: wrappingKey,
                vaultID: vaultID,
                nonce: nonce
            )
            try BiometricVaultEnvelope.saveAtomically(envelope, to: biometricEnvelopeURL)
        } catch {
            try? biometricKeyStore.delete(vaultID: vaultID)
            try? FileManager.default.removeItem(at: biometricEnvelopeURL)
            throw VaultSessionError.biometricSetupFailed
        }
    }

    public func disableBiometricUnlock() throws {
        let vaultID: UUID
        do {
            vaultID = try biometricVaultID()
        } catch {
            throw VaultSessionError.biometricCleanupFailed
        }

        var cleanupFailed = false
        do {
            try biometricKeyStore.delete(vaultID: vaultID)
        } catch {
            cleanupFailed = true
        }
        do {
            if FileManager.default.fileExists(atPath: biometricEnvelopeURL.path) {
                try FileManager.default.removeItem(at: biometricEnvelopeURL)
            }
        } catch {
            cleanupFailed = true
        }
        if cleanupFailed {
            throw VaultSessionError.biometricCleanupFailed
        }
    }

    public func unlockWithBiometrics(context: LAContext?) throws {
        guard !isUnlocked else { throw VaultSessionError.alreadyUnlocked }
        do {
            let vaultID = try biometricVaultID()
            var wrappingKey = try biometricKeyStore.read(vaultID: vaultID, context: context)
            defer { wrappingKey.resetBytes(in: 0..<wrappingKey.count) }
            let envelope = try Data(contentsOf: biometricEnvelopeURL)
            var unlockedVaultKey = try BiometricVaultEnvelope.open(
                envelope,
                wrappingKey: wrappingKey,
                expectedVaultID: vaultID
            )
            defer { unlockedVaultKey.resetBytes(in: 0..<unlockedVaultKey.count) }
            database = try openDatabase(vaultKey: unlockedVaultKey)
            vaultKey = Data(unlockedVaultKey)
            unlockMethod = .biometric
        } catch {
            try? disableBiometricUnlock()
            throw VaultSessionError.biometricUnlockFailed
        }
    }

    public func loginItemRepository() throws -> LoginItemRepository {
        guard let database else { throw VaultSessionError.locked }
        return LoginItemRepository(database: database)
    }

    /// Exports a portable archive without exposing this vault's database key or master password.
    /// The destination must not already exist, avoiding an accidental overwrite of another archive.
    public func exportArchive(to targetURL: URL, exportPassword: String) throws {
        guard let database else { throw VaultSessionError.locked }
        let fileManager = FileManager.default
        let temporaryURL = targetURL.deletingLastPathComponent().appendingPathComponent(
            ".\(targetURL.lastPathComponent).\(UUID().uuidString).tmp", isDirectory: false
        )
        defer { try? fileManager.removeItem(at: temporaryURL) }

        do {
            guard !fileManager.fileExists(atPath: targetURL.path) else { throw VaultSessionError.archiveExportFailed }
            let metadata = try metadataStore.load()
            let records = try LoginItemRepository(database: database).search(query: "").map(pwdlockRecord)
            let sourceVaultID = try uuid(from: metadata.vaultID)
            let payload = PwdlockPayload(
                exportId: UUID(),
                sourceVaultId: sourceVaultID,
                createdAtMs: milliseconds(Date()),
                records: records
            )
            let bytes = try PwdlockArchive.export(payload: payload, password: exportPassword)
            try bytes.write(to: temporaryURL, options: .withoutOverwriting)
            try synchronizeFile(at: temporaryURL)
            _ = try PwdlockArchive.import(data: Data(contentsOf: temporaryURL), password: exportPassword)
            try publishArchiveWithoutReplacing(from: temporaryURL, to: targetURL)
            try synchronizeDirectory(targetURL.deletingLastPathComponent())
        } catch let error as VaultSessionError {
            throw error
        } catch {
            throw VaultSessionError.archiveExportFailed
        }
    }

    /// Authenticates and merges a portable archive into the currently unlocked vault.
    /// Login inserts and conflict creation are committed as one database transaction.
    public func mergeArchive(at archiveURL: URL, exportPassword: String) throws -> ImportMergeSummary {
        guard isUnlocked else { throw VaultSessionError.locked }
        let archiveData = try readVerifiedArchive(at: archiveURL)
        let payload = try PwdlockArchive.import(data: archiveData, password: exportPassword)
        let importedItems = try payload.records.map(loginItem)
        let metadata = try metadataStore.load()
        return try loginItemRepository().mergeImportedItems(
            importedItems,
            importedSourceVaultID: payload.sourceVaultId,
            localSourceVaultID: try uuid(from: metadata.vaultID)
        )
    }

    /// Imports a verified portable archive only into an empty local vault directory.
    /// Archive authentication and strict payload validation finish before this creates
    /// any local vault files, and imported records are committed atomically.
    public func importArchive(at archiveURL: URL, exportPassword: String, newMasterPassword: String) throws {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: directory.path) else { throw VaultSessionError.vaultAlreadyExists }
        guard !isUnlocked else { throw VaultSessionError.alreadyUnlocked }

        let archiveData = try readVerifiedArchive(at: archiveURL)

        let payload: PwdlockPayload
        do {
            payload = try PwdlockArchive.import(data: archiveData, password: exportPassword)
        } catch let error as PwdlockArchiveError {
            throw error
        } catch {
            throw VaultSessionError.archiveImportFailed
        }
        guard MasterPasswordPolicy.isValid(newMasterPassword) else {
            throw VaultSessionError.masterPasswordTooShort
        }
        guard !fileManager.fileExists(atPath: directory.path) else { throw VaultSessionError.vaultAlreadyExists }

        let parentDirectory = directory.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: parentDirectory.path) else {
            throw VaultSessionError.archiveImportFailed
        }
        let stagingDirectory = parentDirectory.appendingPathComponent(
            ".\(directory.lastPathComponent).import.\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fileManager.removeItem(at: stagingDirectory) }
        do {
            try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: false)
            let stagedSession = VaultSession(directory: stagingDirectory)
            try stagedSession.create(masterPassword: newMasterPassword)
            let importedItems = try payload.records.map(loginItem)
            try stagedSession.loginItemRepository().createAll(importedItems)
            guard let stagedVaultKey = stagedSession.vaultKey else {
                throw VaultSessionError.archiveImportFailed
            }
            let importedVaultKey = Data(stagedVaultKey)
            stagedSession.lock()
            try synchronizeDirectory(stagingDirectory)
            try stagedVaultPublisher(stagingDirectory, directory)
            database = try openDatabase(vaultKey: importedVaultKey)
            vaultKey = importedVaultKey
            unlockMethod = .masterPassword
        } catch let error as VaultSessionError {
            throw error
        } catch {
            throw VaultSessionError.archiveImportFailed
        }
    }

    /// Makes an encrypted, self-contained database snapshot inside this vault's
    /// private `Backups` directory. Callers receive only the backup file URL.
    @discardableResult
    public func createLocalBackup() throws -> URL {
        guard let database, let vaultKey else { throw VaultSessionError.locked }

        let fileManager = FileManager.default
        let backupsDirectory = directory.appendingPathComponent("Backups", isDirectory: true)
        do {
            try fileManager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
            let backupURL = backupsDirectory.appendingPathComponent(
                "vault-\(Int64(Date().timeIntervalSince1970 * 1_000)).\(UUID().uuidString).db",
                isDirectory: false
            )
            let temporaryURL = backupsDirectory.appendingPathComponent(
                ".\(backupURL.lastPathComponent).\(UUID().uuidString).tmp",
                isDirectory: false
            )
            defer { try? fileManager.removeItem(at: temporaryURL) }

            try database.createEncryptedBackup(at: temporaryURL, vaultKey: vaultKey)
            try synchronizeFile(at: temporaryURL)
            try validateEncryptedDatabase(at: temporaryURL, vaultKey: vaultKey)
            try moveAtomically(from: temporaryURL, to: backupURL, replacingDestination: false)
            try synchronizeDirectory(backupsDirectory)
            try validateEncryptedDatabase(at: backupURL, vaultKey: vaultKey)
            return backupURL
        } catch let error as VaultSessionError {
            throw error
        } catch {
            throw VaultSessionError.backupFailed
        }
    }

    /// Restores one previously-created local backup. Validation completes before
    /// the live database is closed, so an invalid or truncated backup cannot
    /// modify the current vault.
    public func restoreLocalBackup(at backupURL: URL) throws {
        guard let vaultKey, database != nil else { throw VaultSessionError.locked }
        guard isLocalBackupURL(backupURL) else { throw VaultSessionError.backupNotFound }

        let fileManager = FileManager.default
        let stagedURL = directory.appendingPathComponent(".vault.restore.\(UUID().uuidString).tmp", isDirectory: false)
        defer { try? fileManager.removeItem(at: stagedURL) }

        do {
            try fileManager.copyItem(at: backupURL, to: stagedURL)
            try synchronizeFile(at: stagedURL)
        } catch {
            throw VaultSessionError.backupValidationFailed
        }

        do {
            try validateEncryptedDatabase(at: stagedURL, vaultKey: vaultKey)
        } catch {
            throw VaultSessionError.backupValidationFailed
        }

        let databaseURL = directory.appendingPathComponent("vault.db", isDirectory: false)
        database?.close()
        database = nil

        do {
            try removeSQLiteSidecars(for: databaseURL)
            try moveAtomically(from: stagedURL, to: databaseURL, replacingDestination: true)
            try synchronizeDirectory(directory)
            database = try openDatabase(vaultKey: vaultKey)
        } catch {
            if database == nil, fileManager.fileExists(atPath: databaseURL.path) {
                database = try? openDatabase(vaultKey: vaultKey)
            }
            throw VaultSessionError.restoreFailed
        }
    }

    public func restoreLatestLocalBackup() throws {
        guard isUnlocked else { throw VaultSessionError.locked }
        let backupsDirectory = directory.appendingPathComponent("Backups", isDirectory: true)
        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: backupsDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw VaultSessionError.backupNotFound
        }
        let latest = contents
            .filter { $0.pathExtension == "db" && isLocalBackupURL($0) }
            .max { modificationDate(of: $0) < modificationDate(of: $1) }
        guard let latest else {
            throw VaultSessionError.backupNotFound
        }
        try restoreLocalBackup(at: latest)
    }

    private func openDatabase(vaultKey: Data) throws -> EncryptedDatabase {
        let database = try EncryptedDatabase.open(
            at: directory.appendingPathComponent("vault.db", isDirectory: false),
            vaultKey: vaultKey
        )
        try LoginItemRepository(database: database).migrate()
        return database
    }

    private func localVaultExists() -> Bool {
        let fileManager = FileManager.default
        return ["vault.meta", "vault.db"].contains {
            fileManager.fileExists(atPath: directory.appendingPathComponent($0, isDirectory: false).path)
        }
    }

    private func verifiedFileSize(of handle: FileHandle) throws -> Int {
        var fileStatus = stat()
        guard fstat(handle.fileDescriptor, &fileStatus) == 0 else {
            throw VaultSessionError.archiveImportFailed
        }
        guard fileStatus.st_size >= 0, fileStatus.st_size <= off_t(Int.max) else {
            throw PwdlockArchiveError.invalidArchive
        }
        return Int(fileStatus.st_size)
    }

    private func readVerifiedArchive(at archiveURL: URL) throws -> Data {
        do {
            let handle = try FileHandle(forReadingFrom: archiveURL)
            defer { try? handle.close() }
            let archiveSize = try verifiedFileSize(of: handle)
            guard archiveSize <= PwdlockArchive.maximumFileBytes else {
                throw PwdlockArchiveError.invalidArchive
            }
            let archiveData = try archiveDataReader(handle, archiveSize)
            guard archiveData.count == archiveSize,
                  try verifiedFileSize(of: handle) == archiveSize else {
                throw PwdlockArchiveError.invalidArchive
            }
            return archiveData
        } catch let error as PwdlockArchiveError {
            throw error
        } catch let error as VaultSessionError {
            throw error
        } catch {
            throw VaultSessionError.archiveImportFailed
        }
    }

    private static func readVerifiedArchive(from handle: FileHandle, byteCount: Int) throws -> Data {
        let data = try handle.read(upToCount: byteCount) ?? Data()
        guard data.count == byteCount else { throw PwdlockArchiveError.invalidArchive }
        return data
    }

    private func loginItem(_ record: PwdlockRecord) throws -> LoginItem {
        guard let revision = Int(exactly: record.revision) else {
            throw VaultSessionError.archiveImportFailed
        }
        return LoginItem(
            id: record.id, title: record.title, username: record.username, password: record.password,
            url: record.url, category: record.category, note: record.note,
            createdAt: Date(timeIntervalSince1970: TimeInterval(record.createdAtMs) / 1_000),
            updatedAt: Date(timeIntervalSince1970: TimeInterval(record.updatedAtMs) / 1_000),
            revision: revision, deviceID: record.deviceId
        )
    }

    private static func publishStagedVault(from stagingURL: URL, to targetURL: URL) throws {
        let status = stagingURL.path.withCString { stagingPath in
            targetURL.path.withCString { targetPath in
                renameatx_np(AT_FDCWD, stagingPath, AT_FDCWD, targetPath, UInt32(RENAME_EXCL))
            }
        }
        guard status == 0 else {
            if errno == EEXIST { throw VaultSessionError.vaultAlreadyExists }
            throw VaultSessionError.archiveImportFailed
        }
    }

    private func validateEncryptedDatabase(at url: URL, vaultKey: Data) throws {
        let database = try EncryptedDatabase.open(at: url, vaultKey: vaultKey)
        defer { database.close() }
        guard try database.scalarText("PRAGMA integrity_check") == "ok" else {
            throw VaultSessionError.backupValidationFailed
        }
        let repository = LoginItemRepository(database: database)
        _ = try repository.search(query: "")
        _ = try repository.pendingConflicts()
    }

    private func isLocalBackupURL(_ url: URL) -> Bool {
        let backupsDirectory = directory.appendingPathComponent("Backups", isDirectory: true).standardizedFileURL
        return url.deletingLastPathComponent().standardizedFileURL == backupsDirectory
            && FileManager.default.fileExists(atPath: url.path)
    }

    private func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private func synchronizeFile(at url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.synchronize()
    }

    private func synchronizeDirectory(_ directory: URL) throws {
        let descriptor = directory.path.withCString { open($0, O_RDONLY) }
        guard descriptor >= 0 else { throw VaultSessionError.backupFailed }
        defer { _ = close(descriptor) }
        guard fsync(descriptor) == 0 else { throw VaultSessionError.backupFailed }
    }

    private func moveAtomically(from source: URL, to destination: URL, replacingDestination: Bool) throws {
        if !replacingDestination, FileManager.default.fileExists(atPath: destination.path) {
            throw VaultSessionError.backupFailed
        }
        let status = source.path.withCString { sourcePath in
            destination.path.withCString { destinationPath in
                rename(sourcePath, destinationPath)
            }
        }
        guard status == 0 else { throw VaultSessionError.backupFailed }
    }

    /// `link` atomically creates the destination name only if it does not exist.
    /// Both paths are siblings, so they are always on the same filesystem.
    private func publishArchiveWithoutReplacing(from temporaryURL: URL, to targetURL: URL) throws {
        let status = temporaryURL.path.withCString { temporaryPath in
            targetURL.path.withCString { targetPath in
                link(temporaryPath, targetPath)
            }
        }
        guard status == 0 else { throw VaultSessionError.archiveExportFailed }
        do {
            try FileManager.default.removeItem(at: temporaryURL)
        } catch {
            throw VaultSessionError.archiveExportFailed
        }
    }

    private func removeSQLiteSidecars(for databaseURL: URL) throws {
        let fileManager = FileManager.default
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: databaseURL.path + suffix)
            if fileManager.fileExists(atPath: sidecar.path) {
                try fileManager.removeItem(at: sidecar)
            }
        }
    }

    private func clearRetainedVaultKey() {
        guard let vaultKey else { return }
        self.vaultKey?.resetBytes(in: 0..<vaultKey.count)
        self.vaultKey = nil
    }

    private var biometricEnvelopeURL: URL {
        directory.appendingPathComponent("vault.biometric", isDirectory: false)
    }

    private func biometricVaultID() throws -> UUID {
        try uuid(from: metadataStore.load().vaultID)
    }

    private func pwdlockRecord(_ item: LoginItem) throws -> PwdlockRecord {
        guard let revision = Int64(exactly: item.revision) else { throw VaultSessionError.archiveExportFailed }
        return PwdlockRecord(
            id: item.id, title: item.title, username: item.username, password: item.password,
            url: item.url, category: item.category, note: item.note,
            createdAtMs: milliseconds(item.createdAt), updatedAtMs: milliseconds(item.updatedAt),
            revision: revision, deviceId: item.deviceID
        )
    }

    private func milliseconds(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1_000)
    }

    private func uuid(from bytes: Data) throws -> UUID {
        guard bytes.count == 16 else { throw VaultSessionError.archiveExportFailed }
        // VaultMetadataCodec returns Data slices, whose valid indices need not start at zero.
        // Rebase before indexing the raw identifier.
        var canonical = Data(bytes)
        canonical[6] = (canonical[6] & 0x0f) | 0x40
        canonical[8] = (canonical[8] & 0x3f) | 0x80
        let hex = canonical.map { String(format: "%02x", $0) }.joined()
        guard let uuid = UUID(uuidString: "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20))") else {
            throw VaultSessionError.archiveExportFailed
        }
        return uuid
    }
}
