import Foundation
import LocalAuthentication
import Testing
@testable import PwdlockCore

@Test("only a master-password session can enable and rebuild Touch ID unlock")
func enablesBiometricUnlockAfterMasterPassword() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let password = "correct horse battery staple"
    let keyStore = SessionTestBiometricKeyStore()
    let session = VaultSession(
        directory: directory,
        biometricKeyStore: keyStore,
        randomBytes: { Data(repeating: 0x5a, count: $0) }
    )
    try session.create(masterPassword: password)
    session.lock()
    try session.unlock(masterPassword: password)

    try session.enableBiometricUnlock()

    #expect(session.unlockMethod == .masterPassword)
    #expect(session.isBiometricUnlockConfigured)
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("vault.biometric").path))
    session.lock()
    try session.unlockWithBiometrics(context: nil)
    #expect(session.unlockMethod == .biometric)
    #expect(throws: VaultSessionError.masterPasswordUnlockRequired) {
        try session.enableBiometricUnlock()
    }

    try session.disableBiometricUnlock()
    #expect(!session.isBiometricUnlockConfigured)
    #expect(!keyStore.containsAnyKey)
    #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("vault.biometric").path))
}

@Test("damaged biometric material is removed while the vault remains locked")
func damagedBiometricMaterialFailsClosed() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let password = "correct horse battery staple"
    let keyStore = SessionTestBiometricKeyStore()
    let session = VaultSession(
        directory: directory,
        biometricKeyStore: keyStore,
        randomBytes: { Data(repeating: 0x33, count: $0) }
    )
    try session.create(masterPassword: password)
    session.lock()
    try session.unlock(masterPassword: password)
    try session.enableBiometricUnlock()
    session.lock()
    let envelopeURL = directory.appendingPathComponent("vault.biometric")
    var damaged = try Data(contentsOf: envelopeURL)
    damaged[40] ^= 0xff
    try damaged.write(to: envelopeURL)

    #expect(throws: VaultSessionError.biometricUnlockFailed) {
        try session.unlockWithBiometrics(context: nil)
    }

    #expect(!session.isUnlocked)
    #expect(!session.isBiometricUnlockConfigured)
    #expect(!keyStore.containsAnyKey)
    #expect(!FileManager.default.fileExists(atPath: envelopeURL.path))
}

@Test("changing the master password removes biometric unlock material")
func changingMasterPasswordDisablesBiometricUnlock() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let keyStore = SessionTestBiometricKeyStore()
    let session = VaultSession(
        directory: directory,
        biometricKeyStore: keyStore,
        randomBytes: { Data(repeating: 0x66, count: $0) }
    )
    let oldPassword = "correct horse battery staple"
    let newPassword = "new correct horse battery staple"
    try session.create(masterPassword: oldPassword)
    session.lock()
    try session.unlock(masterPassword: oldPassword)
    try session.enableBiometricUnlock()

    try session.changeMasterPassword(currentPassword: oldPassword, newPassword: newPassword)

    #expect(!session.isBiometricUnlockConfigured)
    #expect(!keyStore.containsAnyKey)
    #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("vault.biometric").path))
    session.lock()
    try session.unlock(masterPassword: newPassword)
    #expect(session.unlockMethod == .masterPassword)
}

@Test("biometric cleanup failure leaves the existing master password unchanged")
func biometricCleanupFailureDoesNotChangeMasterPassword() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let keyStore = SessionTestBiometricKeyStore()
    let session = VaultSession(
        directory: directory,
        biometricKeyStore: keyStore,
        randomBytes: { Data(repeating: 0x68, count: $0) }
    )
    let oldPassword = "correct horse battery staple"
    let newPassword = "new correct horse battery staple"
    try session.create(masterPassword: oldPassword)
    session.lock()
    try session.unlock(masterPassword: oldPassword)
    try session.enableBiometricUnlock()
    keyStore.failDeletion = true

    #expect(throws: VaultSessionError.biometricCleanupFailed) {
        try session.changeMasterPassword(currentPassword: oldPassword, newPassword: newPassword)
    }

    keyStore.failDeletion = false
    session.lock()
    try session.unlock(masterPassword: oldPassword)
    session.lock()
    #expect(throws: VaultKeyEnvelopeError.authenticationFailed) {
        try session.unlock(masterPassword: newPassword)
    }
}

@Test("failed biometric setup removes a Keychain key created earlier in the operation")
func failedBiometricSetupRollsBackMaterial() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let keyStore = SessionTestBiometricKeyStore()
    let session = VaultSession(
        directory: directory,
        biometricKeyStore: keyStore,
        randomBytes: { count in Data(repeating: 0x77, count: count == 12 ? 11 : count) }
    )
    let password = "correct horse battery staple"
    try session.create(masterPassword: password)
    session.lock()
    try session.unlock(masterPassword: password)

    #expect(throws: VaultSessionError.biometricSetupFailed) {
        try session.enableBiometricUnlock()
    }

    #expect(!session.isBiometricUnlockConfigured)
    #expect(!keyStore.containsAnyKey)
    #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("vault.biometric").path))
}

@Test("local backup and portable export do not transfer biometric unlock material")
func backupAndArchiveExcludeBiometricMaterial() throws {
    let sourceDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let targetDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let archiveURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(UUID().uuidString).pwdlock")
    defer {
        try? FileManager.default.removeItem(at: sourceDirectory)
        try? FileManager.default.removeItem(at: targetDirectory)
        try? FileManager.default.removeItem(at: archiveURL)
    }
    let sourceKeyStore = SessionTestBiometricKeyStore()
    let source = VaultSession(
        directory: sourceDirectory,
        biometricKeyStore: sourceKeyStore,
        randomBytes: { Data(repeating: 0x22, count: $0) }
    )
    let password = "correct horse battery staple"
    try source.create(masterPassword: password)
    source.lock()
    try source.unlock(masterPassword: password)
    try source.enableBiometricUnlock()

    let backupURL = try source.createLocalBackup()
    try source.exportArchive(to: archiveURL, exportPassword: "separate export password")

    #expect(FileManager.default.fileExists(atPath: sourceDirectory.appendingPathComponent("vault.biometric").path))
    #expect(backupURL.deletingLastPathComponent().lastPathComponent == "Backups")
    #expect(
        try FileManager.default.contentsOfDirectory(atPath: backupURL.deletingLastPathComponent().path)
            == [backupURL.lastPathComponent]
    )
    let targetKeyStore = SessionTestBiometricKeyStore()
    let target = VaultSession(directory: targetDirectory, biometricKeyStore: targetKeyStore)
    try target.importArchive(
        at: archiveURL,
        exportPassword: "separate export password",
        newMasterPassword: "target correct horse battery staple"
    )
    #expect(!target.isBiometricUnlockConfigured)
    #expect(!targetKeyStore.containsAnyKey)
    #expect(!FileManager.default.fileExists(atPath: targetDirectory.appendingPathComponent("vault.biometric").path))
}

@Test("vault session rejects a master password shorter than 12 Unicode characters during creation")
func rejectsShortMasterPasswordDuringCreation() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let session = VaultSession(directory: directory)

    do {
        try session.create(masterPassword: String(repeating: "🔐", count: 11))
        Issue.record("Expected a short master password to be rejected.")
    } catch {
        #expect(error as? VaultSessionError == .masterPasswordTooShort)
    }
    #expect(!session.isUnlocked)
}

@Test("vault session allows a 12-character Unicode master passphrase")
func allowsTwelveCharacterUnicodeMasterPassphrase() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let session = VaultSession(directory: directory)
    let masterPassword = String(repeating: "🔐", count: 12)

    try session.create(masterPassword: masterPassword)
    session.lock()

    let reopenedSession = VaultSession(directory: directory)
    try reopenedSession.unlock(masterPassword: masterPassword)

    #expect(reopenedSession.isUnlocked)
}

@Test("vault session rejects a replacement master password shorter than 12 Unicode characters")
func rejectsShortReplacementMasterPassword() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let session = VaultSession(directory: directory)
    let currentPassword = "correct horse battery staple"

    try session.create(masterPassword: currentPassword)

    do {
        try session.changeMasterPassword(
            currentPassword: currentPassword,
            newPassword: String(repeating: "🔐", count: 11)
        )
        Issue.record("Expected a short replacement master password to be rejected.")
    } catch {
        #expect(error as? VaultSessionError == .masterPasswordTooShort)
    }
}

@Test("vault session creates, locks, and unlocks the same local vault")
func createsLocksAndUnlocksVault() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let firstSession = VaultSession(directory: directory)
    try firstSession.create(masterPassword: "correct horse battery staple")
    #expect(firstSession.isUnlocked)

    firstSession.lock()
    #expect(!firstSession.isUnlocked)

    let reopenedSession = VaultSession(directory: directory)
    try reopenedSession.unlock(masterPassword: "correct horse battery staple")

    #expect(reopenedSession.isUnlocked)
}

@Test("vault session changes the master password without re-encrypting the database")
func changesMasterPassword() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let session = VaultSession(directory: directory)
    try session.create(masterPassword: "old password")
    try session.changeMasterPassword(currentPassword: "old password", newPassword: "new password")
    session.lock()

    let reopenedSession = VaultSession(directory: directory)
    #expect(throws: VaultKeyEnvelopeError.authenticationFailed) {
        try reopenedSession.unlock(masterPassword: "old password")
    }
    try reopenedSession.unlock(masterPassword: "new password")

    #expect(reopenedSession.isUnlocked)
}

@Test("locked vault session does not expose a login item repository")
func preventsRepositoryAccessWhenLocked() throws {
    let session = VaultSession(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))

    #expect(throws: VaultSessionError.locked) {
        _ = try session.loginItemRepository()
    }
}

@Test("vault session exports all login items to a verified portable archive")
func exportsPortableArchive() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let target = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pwdlock", isDirectory: false)
    defer { try? FileManager.default.removeItem(at: target) }
    let session = VaultSession(directory: directory)
    try session.create(masterPassword: "correct horse battery staple")
    let item = backupTestLoginItem(title: "Portable login")
    try session.loginItemRepository().create(item)

    try session.exportArchive(to: target, exportPassword: "portable password")

    let payload = try PwdlockArchive.import(data: Data(contentsOf: target), password: "portable password")
    #expect(payload.records.count == 1)
    #expect(payload.records[0].id == item.id)
    #expect(payload.records[0].password == item.password)
}

@Test("vault session export never replaces an existing portable archive")
func exportArchivePreservesExistingTarget() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let target = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pwdlock", isDirectory: false)
    defer { try? FileManager.default.removeItem(at: target) }
    let original = Data("existing archive must remain intact".utf8)
    try original.write(to: target)
    let session = VaultSession(directory: directory)
    try session.create(masterPassword: "correct horse battery staple")

    #expect(throws: VaultSessionError.archiveExportFailed) {
        try session.exportArchive(to: target, exportPassword: "portable password")
    }
    #expect(try Data(contentsOf: target) == original)
}

@Test("vault session exports a stable RFC 4122 source identifier for arbitrary legacy vault bytes")
func exportsCanonicalSourceVaultIDForRawVaultBytes() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let target = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pwdlock", isDirectory: false)
    defer { try? FileManager.default.removeItem(at: target) }
    let password = "correct horse battery staple"
    let vaultKey = Data(repeating: 0x5a, count: 32)
    let metadata = try VaultKeyEnvelope.wrap(
        vaultKey: vaultKey, masterPassword: password, vaultID: Data((0...15).map(UInt8.init)),
        passwordSalt: Data(repeating: 0x11, count: 16), wrapNonce: Data(repeating: 0x22, count: 12), parameters: .initial
    )
    try VaultMetadataStore(directory: directory).save(metadata)
    let database = try EncryptedDatabase.open(at: directory.appendingPathComponent("vault.db"), vaultKey: vaultKey)
    let repository = LoginItemRepository(database: database)
    try repository.migrate()
    try repository.create(backupTestLoginItem(title: "Raw identifier login"))
    database.close()

    let session = VaultSession(directory: directory)
    try session.unlock(masterPassword: password)
    try session.exportArchive(to: target, exportPassword: "portable password")

    let payload = try PwdlockArchive.import(data: Data(contentsOf: target), password: "portable password")
    #expect(payload.sourceVaultId.uuidString == "00010203-0405-4607-8809-0A0B0C0D0E0F")
}

@Test("vault session imports an authenticated archive into a fresh vault and preserves login records")
func importsPortableArchiveIntoFreshVault() throws {
    let sourceDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let targetDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let archiveURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pwdlock", isDirectory: false)
    defer {
        try? FileManager.default.removeItem(at: sourceDirectory)
        try? FileManager.default.removeItem(at: targetDirectory)
        try? FileManager.default.removeItem(at: archiveURL)
    }
    let source = VaultSession(directory: sourceDirectory)
    let first = backupTestLoginItem(title: "Imported login")
    let second = LoginItem(
        id: UUID(), title: "Second imported login", username: "person@example.com", password: "another-secret",
        url: "https://example.org", category: "Work", note: "Imported note",
        createdAt: Date(timeIntervalSince1970: 1_760_000_100), updatedAt: Date(timeIntervalSince1970: 1_760_000_200),
        revision: 7, deviceID: UUID()
    )
    try source.create(masterPassword: "source master password")
    try source.loginItemRepository().create(first)
    try source.loginItemRepository().create(second)
    try source.exportArchive(to: archiveURL, exportPassword: "separate export password")

    let target = VaultSession(directory: targetDirectory)
    try target.importArchive(
        at: archiveURL,
        exportPassword: "separate export password",
        newMasterPassword: "target master password"
    )

    #expect(try target.loginItemRepository().item(id: first.id) == first)
    #expect(try target.loginItemRepository().item(id: second.id) == second)
    target.lock()
    let reopened = VaultSession(directory: targetDirectory)
    try reopened.unlock(masterPassword: "target master password")
    #expect(try reopened.loginItemRepository().item(id: first.id) == first)
    #expect(try reopened.loginItemRepository().item(id: second.id) == second)
}

@Test("unlocked vault session merges a portable archive into the existing vault")
func importsPortableArchiveIntoUnlockedVault() throws {
    let sourceDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let targetDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let archiveURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pwdlock", isDirectory: false)
    defer {
        try? FileManager.default.removeItem(at: sourceDirectory)
        try? FileManager.default.removeItem(at: targetDirectory)
        try? FileManager.default.removeItem(at: archiveURL)
    }
    let imported = backupTestLoginItem(title: "导入登录")
    let source = VaultSession(directory: sourceDirectory)
    try source.create(masterPassword: "source master password")
    try source.loginItemRepository().create(imported)
    try source.exportArchive(to: archiveURL, exportPassword: "separate export password")

    let target = VaultSession(directory: targetDirectory)
    try target.create(masterPassword: "target master password")
    let summary = try target.mergeArchive(
        at: archiveURL,
        exportPassword: "separate export password"
    )

    #expect(summary == ImportMergeSummary(added: 1, identical: 0, conflicts: 0))
    #expect(try target.loginItemRepository().item(id: imported.id) == imported)
}

@Test("wrong archive password leaves a fresh target without a local vault")
func wrongArchivePasswordDoesNotCreateTargetVault() throws {
    let sourceDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let targetDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let archiveURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pwdlock", isDirectory: false)
    defer {
        try? FileManager.default.removeItem(at: sourceDirectory)
        try? FileManager.default.removeItem(at: targetDirectory)
        try? FileManager.default.removeItem(at: archiveURL)
    }
    let source = VaultSession(directory: sourceDirectory)
    try source.create(masterPassword: "source master password")
    try source.exportArchive(to: archiveURL, exportPassword: "separate export password")

    #expect(throws: PwdlockArchiveError.authenticationFailed) {
        try VaultSession(directory: targetDirectory).importArchive(
            at: archiveURL,
            exportPassword: "wrong export password",
            newMasterPassword: "target master password"
        )
    }
    #expect(!FileManager.default.fileExists(atPath: targetDirectory.appendingPathComponent("vault.meta").path))
    #expect(!FileManager.default.fileExists(atPath: targetDirectory.appendingPathComponent("vault.db").path))
}

@Test("archive import never overwrites an existing local vault")
func importArchivePreservesExistingVault() throws {
    let sourceDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let targetDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let archiveURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pwdlock", isDirectory: false)
    defer {
        try? FileManager.default.removeItem(at: sourceDirectory)
        try? FileManager.default.removeItem(at: targetDirectory)
        try? FileManager.default.removeItem(at: archiveURL)
    }
    let source = VaultSession(directory: sourceDirectory)
    try source.create(masterPassword: "source master password")
    try source.loginItemRepository().create(backupTestLoginItem(title: "Source login"))
    try source.exportArchive(to: archiveURL, exportPassword: "separate export password")

    let target = VaultSession(directory: targetDirectory)
    let original = backupTestLoginItem(title: "Existing target login")
    try target.create(masterPassword: "existing target password")
    try target.loginItemRepository().create(original)

    #expect(throws: VaultSessionError.vaultAlreadyExists) {
        try target.importArchive(
            at: archiveURL,
            exportPassword: "separate export password",
            newMasterPassword: "target master password"
        )
    }
    #expect(try target.loginItemRepository().item(id: original.id) == original)
}

@Test("archive import rejects an invalid new local master password without creating a vault")
func importArchiveRejectsShortNewMasterPassword() throws {
    let sourceDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let targetDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let archiveURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pwdlock", isDirectory: false)
    defer {
        try? FileManager.default.removeItem(at: sourceDirectory)
        try? FileManager.default.removeItem(at: targetDirectory)
        try? FileManager.default.removeItem(at: archiveURL)
    }
    let source = VaultSession(directory: sourceDirectory)
    try source.create(masterPassword: "source master password")
    try source.exportArchive(to: archiveURL, exportPassword: "separate export password")

    #expect(throws: VaultSessionError.masterPasswordTooShort) {
        try VaultSession(directory: targetDirectory).importArchive(
            at: archiveURL,
            exportPassword: "separate export password",
            newMasterPassword: "short"
        )
    }
    #expect(!FileManager.default.fileExists(atPath: targetDirectory.appendingPathComponent("vault.meta").path))
    #expect(!FileManager.default.fileExists(atPath: targetDirectory.appendingPathComponent("vault.db").path))
}

@Test("oversize archive is rejected before its bytes are loaded or a target vault is created")
func importArchiveRejectsOversizeFileBeforeLoading() throws {
    let targetDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let archiveURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pwdlock", isDirectory: false)
    defer {
        try? FileManager.default.removeItem(at: targetDirectory)
        try? FileManager.default.removeItem(at: archiveURL)
    }
    FileManager.default.createFile(atPath: archiveURL.path, contents: Data())
    let handle = try FileHandle(forWritingTo: archiveURL)
    try handle.truncate(atOffset: UInt64(100 * 1_024 * 1_024 + 1))
    try handle.close()
    var archiveLoaderWasCalled = false
    let session = VaultSession(directory: targetDirectory, archiveDataReader: { _, _ in
        archiveLoaderWasCalled = true
        return Data()
    })

    #expect(throws: PwdlockArchiveError.invalidArchive) {
        try session.importArchive(
            at: archiveURL,
            exportPassword: "separate export password",
            newMasterPassword: "target master password"
        )
    }
    #expect(!archiveLoaderWasCalled)
    #expect(!FileManager.default.fileExists(atPath: targetDirectory.path))
}

@Test("archive import reads a verified archive through the same bounded file handle")
func importArchiveReadsFromVerifiedFileHandle() throws {
    let sourceDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let targetDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let archiveURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pwdlock", isDirectory: false)
    defer {
        try? FileManager.default.removeItem(at: sourceDirectory)
        try? FileManager.default.removeItem(at: targetDirectory)
        try? FileManager.default.removeItem(at: archiveURL)
    }
    let source = VaultSession(directory: sourceDirectory)
    try source.create(masterPassword: "source master password")
    try source.exportArchive(to: archiveURL, exportPassword: "separate export password")
    var readerWasCalled = false
    var verifiedSize = 0
    var descriptor: Int32 = -1
    let target = VaultSession(directory: targetDirectory, archiveDataReader: { handle, size in
        readerWasCalled = true
        verifiedSize = size
        descriptor = handle.fileDescriptor
        guard let data = try handle.read(upToCount: size) else {
            throw PwdlockArchiveError.invalidArchive
        }
        return data
    })

    try target.importArchive(
        at: archiveURL,
        exportPassword: "separate export password",
        newMasterPassword: "target master password"
    )

    #expect(readerWasCalled)
    #expect(descriptor >= 0)
    #expect(verifiedSize == (try archiveURL.resourceValues(forKeys: [.fileSizeKey]).fileSize))
    #expect(target.isUnlocked)
}

@Test("archive import only cleans its staging directory when publication loses a target-directory race")
func importArchivePreservesTargetCreatedDuringPublication() throws {
    let sourceDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let targetDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let archiveURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pwdlock", isDirectory: false)
    defer {
        try? FileManager.default.removeItem(at: sourceDirectory)
        try? FileManager.default.removeItem(at: targetDirectory)
        try? FileManager.default.removeItem(at: archiveURL)
    }
    let source = VaultSession(directory: sourceDirectory)
    try source.create(masterPassword: "source master password")
    try source.exportArchive(to: archiveURL, exportPassword: "separate export password")
    let targetMetadata = Data("other process vault metadata".utf8)
    let session = VaultSession(directory: targetDirectory, stagedVaultPublisher: { _, destination in
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        try targetMetadata.write(to: destination.appendingPathComponent("vault.meta"))
        throw VaultSessionError.vaultAlreadyExists
    })

    #expect(throws: VaultSessionError.vaultAlreadyExists) {
        try session.importArchive(
            at: archiveURL,
            exportPassword: "separate export password",
            newMasterPassword: "target master password"
        )
    }
    #expect(try Data(contentsOf: targetDirectory.appendingPathComponent("vault.meta")) == targetMetadata)
    #expect(!session.isUnlocked)
}

@Test("local encrypted backup restores the snapshot after a login is deleted")
func restoresLoginFromLocalBackupSnapshot() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let session = VaultSession(directory: directory)
    try session.create(masterPassword: "correct horse battery staple")
    let repository = try session.loginItemRepository()
    let original = backupTestLoginItem(title: "Original login")
    try repository.create(original)

    let backup = try session.createLocalBackup()
    #expect(backup.deletingLastPathComponent().lastPathComponent == "Backups")

    try repository.delete(id: original.id)
    #expect(try repository.item(id: original.id) == nil)

    try session.restoreLocalBackup(at: backup)

    #expect(try session.loginItemRepository().item(id: original.id) == original)
}

@Test("corrupt local backup does not replace the current encrypted database")
func rejectsCorruptLocalBackupWithoutChangingCurrentData() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let session = VaultSession(directory: directory)
    try session.create(masterPassword: "correct horse battery staple")
    let current = backupTestLoginItem(title: "Current login")
    try session.loginItemRepository().create(current)

    let backupsDirectory = directory.appendingPathComponent("Backups", isDirectory: true)
    try FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
    let corruptBackup = backupsDirectory.appendingPathComponent("corrupt.db", isDirectory: false)
    try Data([0x00, 0x01, 0x02]).write(to: corruptBackup)

    #expect(throws: VaultSessionError.backupValidationFailed) {
        try session.restoreLocalBackup(at: corruptBackup)
    }
    #expect(session.isUnlocked)
    #expect(try session.loginItemRepository().item(id: current.id) == current)
}

@Test("encrypted backup with an invalid login schema does not replace current vault data")
func rejectsValidlyEncryptedBackupWithInvalidLoginSchema() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let masterPassword = "correct horse battery staple"
    let created = try VaultBootstrap.create(masterPassword: masterPassword)
    try VaultMetadataStore(directory: directory).save(created.metadata)

    let backupsDirectory = directory.appendingPathComponent("Backups", isDirectory: true)
    try FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
    let invalidBackup = backupsDirectory.appendingPathComponent("invalid-schema.db", isDirectory: false)
    let invalidDatabase = try EncryptedDatabase.open(at: invalidBackup, vaultKey: created.vaultKey)
    try invalidDatabase.execute("CREATE TABLE login_items (id TEXT PRIMARY KEY NOT NULL, title TEXT NOT NULL)")
    invalidDatabase.close()

    let session = VaultSession(directory: directory)
    try session.unlock(masterPassword: masterPassword)
    let current = backupTestLoginItem(title: "Current login")
    try session.loginItemRepository().create(current)

    #expect(throws: VaultSessionError.backupValidationFailed) {
        try session.restoreLocalBackup(at: invalidBackup)
    }
    #expect(session.isUnlocked)
    #expect(try session.loginItemRepository().item(id: current.id) == current)
}

@Test("encrypted backup with a malformed conflict variant does not replace current vault data")
func rejectsValidlyEncryptedBackupWithMalformedConflictPayload() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let masterPassword = "correct horse battery staple"
    let created = try VaultBootstrap.create(masterPassword: masterPassword)
    try VaultMetadataStore(directory: directory).save(created.metadata)

    let backupsDirectory = directory.appendingPathComponent("Backups", isDirectory: true)
    try FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
    let invalidBackup = backupsDirectory.appendingPathComponent("invalid-conflict.db", isDirectory: false)
    let invalidDatabase = try EncryptedDatabase.open(at: invalidBackup, vaultKey: created.vaultKey)
    let invalidRepository = LoginItemRepository(database: invalidDatabase)
    try invalidRepository.migrate()
    let groupID = UUID()
    let recordID = UUID()
    try invalidDatabase.execute(
        "INSERT INTO conflict_groups (id, record_id, title, created_at_ms, state) "
            + "VALUES ('\(groupID.uuidString)', '\(recordID.uuidString)', '损坏冲突', 1760000000000, 'pending')"
    )
    for kind in ["local", "imported"] {
        try invalidDatabase.execute(
            "INSERT INTO conflict_variants (id, group_id, kind, source_vault_id, payload) "
                + "VALUES ('\(UUID().uuidString)', '\(groupID.uuidString)', '\(kind)', '\(UUID().uuidString)', X'00')"
        )
    }
    invalidDatabase.close()

    let session = VaultSession(directory: directory)
    try session.unlock(masterPassword: masterPassword)
    let current = backupTestLoginItem(title: "Current login")
    try session.loginItemRepository().create(current)

    #expect(throws: VaultSessionError.backupValidationFailed) {
        try session.restoreLocalBackup(at: invalidBackup)
    }
    #expect(session.isUnlocked)
    #expect(try session.loginItemRepository().item(id: current.id) == current)
}

@Test("locked vault session rejects local backup and restore")
func rejectsLocalBackupOperationsWhileLocked() throws {
    let session = VaultSession(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))

    #expect(throws: VaultSessionError.locked) {
        _ = try session.createLocalBackup()
    }
    #expect(throws: VaultSessionError.locked) {
        try session.restoreLatestLocalBackup()
    }
}

private func backupTestLoginItem(title: String) -> LoginItem {
    LoginItem(
        id: UUID(),
        title: title,
        username: "name@example.com",
        password: "backup-only-secret",
        url: "https://example.com",
        category: "Personal",
        note: "Backup test",
        createdAt: Date(timeIntervalSince1970: 1_760_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_760_000_000),
        revision: 0,
        deviceID: UUID()
    )
}

private final class SessionTestBiometricKeyStore: BiometricKeyStoring, @unchecked Sendable {
    private var keys: [UUID: Data] = [:]
    var failDeletion = false

    var containsAnyKey: Bool { !keys.isEmpty }

    func create(_ key: Data, vaultID: UUID) throws {
        guard keys[vaultID] == nil else { throw BiometricKeyStoreError.duplicate }
        keys[vaultID] = key
    }

    func read(vaultID: UUID, context: LAContext?) throws -> Data {
        guard let key = keys[vaultID] else { throw BiometricKeyStoreError.notFound }
        return key
    }

    func delete(vaultID: UUID) throws {
        if failDeletion { throw BiometricKeyStoreError.unavailable }
        keys[vaultID] = nil
    }

    func contains(vaultID: UUID) -> Bool {
        keys[vaultID] != nil
    }
}
