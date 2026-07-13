import Foundation
import Testing
@testable import PwdlockMacApp
@testable import PwdlockCore

@MainActor
@Test("vault creation requires a master password with at least 12 Unicode characters")
func creationRequiresTwelveCharacterMasterPassword() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let state = VaultAppState(directory: directory)
    let shortPassword = String(repeating: "🔐", count: 11)

    state.createVault(masterPassword: shortPassword, confirmation: shortPassword)

    #expect(state.screen == .create)
    #expect(state.errorMessage == "主密码至少需要 12 个字符。")
}

@MainActor
@Test("master password changes require a replacement with at least 12 Unicode characters")
func masterPasswordChangeRequiresTwelveCharacters() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let session = VaultSession(directory: directory)
    try session.create(masterPassword: "correct horse battery staple")
    let state = VaultAppState(session: session)
    let shortPassword = String(repeating: "🔐", count: 11)

    state.changeMasterPassword(
        currentPassword: "correct horse battery staple",
        newPassword: shortPassword,
        confirmation: shortPassword
    )

    #expect(state.errorMessage == "主密码至少需要 12 个字符。")
}

@MainActor
@Test("unlock cooldown does not run a valid password through the vault session until it expires")
func cooldownPreventsValidUnlockUntilExpiry() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let masterPassword = "correct horse battery staple"
    let session = VaultSession(directory: directory)
    try session.create(masterPassword: masterPassword)
    session.lock()
    let scheduler = ManualAppScheduler()
    let clipboard = RecordingClipboard()
    let clock = ManualUnlockClock(now: Date(timeIntervalSince1970: 1_760_000_000))
    let limiter = UnlockRateLimiter(now: { clock.now })
    let state = VaultAppState(
        session: session,
        scheduler: scheduler,
        clipboard: clipboard,
        unlockRateLimiter: limiter
    )

    for _ in 0..<5 {
        state.unlock(masterPassword: "incorrect password")
    }
    state.unlock(masterPassword: masterPassword)

    #expect(!session.isUnlocked)
    #expect(state.errorMessage == "请稍后再试。")

    clock.advance(by: 30)
    state.unlock(masterPassword: masterPassword)

    #expect(session.isUnlocked)
}

@MainActor
@Test("first launch presents vault creation when vault metadata is absent")
func firstLaunchPresentsCreation() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let state = VaultAppState(directory: directory)

    #expect(state.screen == .create)
}

@MainActor
@Test("first-run import opens the library and reports only an item-count summary")
func firstRunImportOpensLibraryWithSummary() throws {
    let sourceDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let targetDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let archiveURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(UUID().uuidString).pwdlock", isDirectory: false)
    defer {
        try? FileManager.default.removeItem(at: sourceDirectory)
        try? FileManager.default.removeItem(at: targetDirectory)
        try? FileManager.default.removeItem(at: archiveURL)
    }
    let source = VaultSession(directory: sourceDirectory)
    let imported = loginItem(title: "Imported", category: "Personal")
    try source.create(masterPassword: "source master password")
    try source.loginItemRepository().create(imported)
    try source.exportArchive(to: archiveURL, exportPassword: "separate export password")
    let state = VaultAppState(directory: targetDirectory)

    state.importArchive(
        at: archiveURL,
        exportPassword: "separate export password",
        exportPasswordConfirmation: "separate export password",
        newMasterPassword: "target master password",
        newMasterPasswordConfirmation: "target master password"
    )

    #expect(state.screen == .library)
    #expect(state.items.map(\.id) == [imported.id])
    #expect(state.operationSummary == "已导入 1 个登录项。")
    #expect(state.errorMessage == nil)
}

@MainActor
@Test("first-run import shows a generic error for an archive authentication failure")
func firstRunImportHidesArchiveAuthenticationDetails() throws {
    let sourceDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let targetDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let archiveURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(UUID().uuidString).pwdlock", isDirectory: false)
    defer {
        try? FileManager.default.removeItem(at: sourceDirectory)
        try? FileManager.default.removeItem(at: targetDirectory)
        try? FileManager.default.removeItem(at: archiveURL)
    }
    let source = VaultSession(directory: sourceDirectory)
    try source.create(masterPassword: "source master password")
    try source.exportArchive(to: archiveURL, exportPassword: "separate export password")
    let state = VaultAppState(directory: targetDirectory)

    state.importArchive(
        at: archiveURL,
        exportPassword: "incorrect export password",
        exportPasswordConfirmation: "incorrect export password",
        newMasterPassword: "target master password",
        newMasterPasswordConfirmation: "target master password"
    )

    #expect(state.screen == .create)
    #expect(state.errorMessage == "无法导入加密文件。")
    #expect(state.operationSummary == nil)
}

@MainActor
@Test("library export writes a portable archive after independent export password confirmation")
func libraryExportWritesPortableArchive() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let archiveURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(UUID().uuidString).pwdlock", isDirectory: false)
    defer {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.removeItem(at: archiveURL)
    }
    let session = VaultSession(directory: directory)
    try session.create(masterPassword: "local master password")
    try session.loginItemRepository().create(loginItem(title: "Exported", category: "Work"))
    let state = VaultAppState(session: session)

    state.exportArchive(
        to: archiveURL,
        exportPassword: "separate export password",
        confirmation: "separate export password"
    )

    #expect(FileManager.default.fileExists(atPath: archiveURL.path))
    #expect(state.operationSummary == "已导出密码库。")
    #expect(state.errorMessage == nil)
}

@MainActor
@Test("an auto-locked session returns the library to the unlock screen")
func lockedSessionReturnsToUnlockScreen() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let session = VaultSession(directory: directory)
    try session.create(masterPassword: "correct horse battery staple")
    let state = VaultAppState(session: session)

    session.lock()
    state.reconcileLockState()

    #expect(state.screen == .unlock)
}

@MainActor
@Test("backgrounding a new vault setup keeps the creation screen visible")
func backgroundingNewVaultSetupKeepsCreationScreen() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let state = VaultAppState(directory: directory)

    state.applicationDidEnterBackground()

    #expect(state.screen == .create)
}

@MainActor
@Test("library state can present master password change without a selected login")
func libraryCanPresentMasterPasswordChangeWithoutSelection() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let session = VaultSession(directory: directory)
    try session.create(masterPassword: "correct horse battery staple")
    let state = VaultAppState(session: session)

    state.presentChangeMasterPassword()

    #expect(state.isChangeMasterPasswordPresented)
}

@MainActor
@Test("library state can create a local encrypted backup without exposing the database")
func libraryStateCreatesLocalBackup() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let session = VaultSession(directory: directory)
    try session.create(masterPassword: "correct horse battery staple")
    let state = VaultAppState(session: session)

    state.createLocalBackup()

    let backups = try FileManager.default.contentsOfDirectory(
        at: directory.appendingPathComponent("Backups", isDirectory: true),
        includingPropertiesForKeys: nil
    )
    #expect(backups.count == 1)
    #expect(state.errorMessage == nil)
}

@MainActor
@Test("typing a title search refreshes vault activity")
func titleSearchRefreshesVaultActivity() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let session = VaultSession(directory: directory)
    try session.create(masterPassword: "correct horse battery staple")
    let scheduler = ManualAppScheduler()
    let state = VaultAppState(session: session, scheduler: scheduler)

    state.recordActivity()
    state.searchText = "bank"
    scheduler.fireFirst()

    #expect(session.isUnlocked)
}

@MainActor
@Test("injected auto-lock scheduler locks the session and immediately resets app state")
func injectedAutoLockSynchronouslyResetsState() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let session = VaultSession(directory: directory)
    try session.create(masterPassword: "correct horse battery staple")
    let scheduler = ManualAppScheduler()
    let state = VaultAppState(session: session, scheduler: scheduler)

    state.recordActivity()
    scheduler.fireLast()

    #expect(!session.isUnlocked)
    #expect(state.screen == .unlock)
}

@MainActor
@Test("auto-lock immediately clears selected secrets and prevents another password copy")
func autoLockClearsSecretsAndPreventsCopy() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let session = VaultSession(directory: directory)
    try session.create(masterPassword: "correct horse battery staple")
    let item = LoginItem(
        id: UUID(), title: "Bank", username: "ada", password: "secret", url: "",
        category: "", note: "", createdAt: .now, updatedAt: .now, revision: 0, deviceID: UUID()
    )
    try session.loginItemRepository().create(item)
    let scheduler = ManualAppScheduler()
    let clipboard = RecordingClipboard()
    let state = VaultAppState(session: session, scheduler: scheduler, clipboard: clipboard)
    state.selectItem(id: item.id)
    state.togglePasswordReveal()

    #expect(state.copySelectedPassword())
    scheduler.fireLast()

    #expect(state.selectedItem == nil)
    #expect(!state.isPasswordRevealed)
    #expect(!state.copySelectedPassword())
    #expect(clipboard.writeCount == 1)
}

@MainActor
@Test("copying a password starts a thirty-second clipboard countdown")
func copyingPasswordStartsThirtySecondClipboardCountdown() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let session = VaultSession(directory: directory)
    try session.create(masterPassword: "correct horse battery staple")
    let item = loginItem(title: "Bank", category: "Work")
    try session.loginItemRepository().create(item)
    let clock = ManualClipboardClock(now: Date(timeIntervalSince1970: 1_760_000_000))
    let state = VaultAppState(
        session: session,
        scheduler: ManualAppScheduler(),
        clipboard: RecordingClipboard(),
        now: { clock.now }
    )
    state.selectItem(id: item.id)

    #expect(state.copySelectedPassword())
    #expect(state.clipboardSecondsRemaining == 30)
}

@MainActor
@Test("manual clipboard clear removes feedback without overwriting a newer clipboard copy")
func manualClipboardClearRemovesFeedbackAndPreservesNewerContent() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let session = VaultSession(directory: directory)
    try session.create(masterPassword: "correct horse battery staple")
    let item = loginItem(title: "Bank", category: "Work")
    try session.loginItemRepository().create(item)
    let clipboard = RecordingClipboard()
    let state = VaultAppState(session: session, scheduler: ManualAppScheduler(), clipboard: clipboard)
    state.selectItem(id: item.id)
    #expect(state.copySelectedPassword())
    clipboard.write("newer user copy")

    state.clearCopiedPassword()

    #expect(state.clipboardSecondsRemaining == nil)
    #expect(clipboard.text == "newer user copy")
}

@MainActor
@Test("clipboard countdown feedback disappears when its expiry is reached")
func clipboardCountdownFeedbackClearsOnExpiry() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let session = VaultSession(directory: directory)
    try session.create(masterPassword: "correct horse battery staple")
    let item = loginItem(title: "Bank", category: "Work")
    try session.loginItemRepository().create(item)
    let scheduler = ManualAppScheduler()
    let clock = ManualClipboardClock(now: Date(timeIntervalSince1970: 1_760_000_000))
    let state = VaultAppState(
        session: session,
        scheduler: scheduler,
        clipboard: RecordingClipboard(),
        now: { clock.now }
    )
    state.selectItem(id: item.id)
    #expect(state.copySelectedPassword())

    clock.advance(by: 30)
    scheduler.fireFirst(after: 1)

    #expect(state.clipboardSecondsRemaining == nil)
}

@MainActor
@Test("background locking clears clipboard countdown feedback")
func backgroundLockClearsClipboardCountdownFeedback() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let session = VaultSession(directory: directory)
    try session.create(masterPassword: "correct horse battery staple")
    let item = loginItem(title: "Bank", category: "Work")
    try session.loginItemRepository().create(item)
    let state = VaultAppState(session: session, scheduler: ManualAppScheduler(), clipboard: RecordingClipboard())
    state.selectItem(id: item.id)
    #expect(state.copySelectedPassword())

    state.applicationDidEnterBackground()

    #expect(state.clipboardSecondsRemaining == nil)
    #expect(state.screen == .unlock)
}

@MainActor
@Test("editing a selected login persists modified fields and increments revision once")
func editsSelectedLoginItem() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let session = VaultSession(directory: directory)
    try session.create(masterPassword: "correct horse battery staple")
    let original = LoginItem(
        id: UUID(), title: "Old title", username: "old@example.com", password: "old-secret",
        url: "https://old.example.com", category: "Work", note: "Old note",
        createdAt: Date(timeIntervalSince1970: 1_760_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_760_000_001), revision: 3, deviceID: UUID()
    )
    try session.loginItemRepository().create(original)
    let state = VaultAppState(session: session)
    state.selectItem(id: original.id)

    state.editSelectedItem(
        title: "New title",
        username: "new@example.com",
        password: "new-secret",
        url: "https://new.example.com",
        category: "Personal",
        note: "New note"
    )

    let expected = LoginItem(
        id: original.id,
        title: "New title",
        username: "new@example.com",
        password: "new-secret",
        url: "https://new.example.com",
        category: "Personal",
        note: "New note",
        createdAt: original.createdAt,
        updatedAt: state.selectedItem!.updatedAt,
        revision: original.revision + 1,
        deviceID: original.deviceID
    )
    #expect(state.selectedItem == expected)
    #expect(try session.loginItemRepository().item(id: original.id) == expected)
    #expect(state.items == [expected])
    #expect(state.selectedItem!.updatedAt > original.updatedAt)
}

@MainActor
@Test("auto-lock duration choices are persisted and schedule their selected timeout")
func autoLockDurationChoicesPersistAndSchedule() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let suiteName = "VaultAppStateTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let session = VaultSession(directory: directory)
    try session.create(masterPassword: "correct horse battery staple")
    let scheduler = ManualAppScheduler()
    let state = VaultAppState(
        session: session,
        scheduler: scheduler,
        clipboard: RecordingClipboard(),
        userDefaults: defaults
    )

    #expect(AutoLockDuration.allCases.map(\.seconds) == [180, 300, 600])
    #expect(state.autoLockDuration == .fiveMinutes)

    for duration in AutoLockDuration.allCases {
        state.setAutoLockDuration(duration)
        #expect(state.autoLockDuration == duration)
    }

    #expect(scheduler.delays == [180, 300, 600])

    let restoredState = VaultAppState(
        session: session,
        scheduler: ManualAppScheduler(),
        clipboard: RecordingClipboard(),
        userDefaults: defaults
    )
    #expect(restoredState.autoLockDuration == .tenMinutes)
}

@MainActor
@Test("a new vault state stores the five-minute auto-lock default")
func vaultStateStoresDefaultAutoLockDuration() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let suiteName = "VaultAppStateTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let state = VaultAppState(
        session: VaultSession(directory: directory),
        scheduler: ManualAppScheduler(),
        clipboard: RecordingClipboard(),
        userDefaults: defaults
    )

    #expect(state.autoLockDuration == .fiveMinutes)
    #expect(defaults.object(forKey: AutoLockDuration.defaultsKey) as? Int == 300)
}

@MainActor
@Test("changing auto-lock duration invalidates the previously scheduled lock")
func changingAutoLockDurationInvalidatesPreviousSchedule() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let session = VaultSession(directory: directory)
    try session.create(masterPassword: "correct horse battery staple")
    let scheduler = ManualAppScheduler()
    let suiteName = "VaultAppStateTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let state = VaultAppState(
        session: session,
        scheduler: scheduler,
        clipboard: RecordingClipboard(),
        userDefaults: defaults
    )

    state.recordActivity()
    state.setAutoLockDuration(.tenMinutes)
    #expect(scheduler.delays == [300, 600])

    scheduler.fireFirst()
    #expect(session.isUnlocked)
    #expect(state.screen == .library)

    scheduler.fireLast()
    #expect(!session.isUnlocked)
    #expect(state.screen == .unlock)
}

@MainActor
@Test("title search and selected category filter the unlocked in-memory library together")
func titleSearchAndCategoryFilterCombineInMemory() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let session = VaultSession(directory: directory)
    try session.create(masterPassword: "correct horse battery staple")
    let bankWork = loginItem(title: "Bank", category: "Work")
    let bankPersonal = loginItem(title: "Bank", category: "Personal")
    let mailWork = loginItem(title: "Mail", category: "Work")
    let uncategorized = loginItem(title: "Notes", category: "  \n ")
    let repository = try session.loginItemRepository()
    try repository.create(bankWork)
    try repository.create(bankPersonal)
    try repository.create(mailWork)
    try repository.create(uncategorized)
    let state = VaultAppState(session: session)

    #expect(state.categories == ["Personal", "Work"])
    #expect(Set(state.items.map(\.id)) == Set([bankWork.id, bankPersonal.id, mailWork.id, uncategorized.id]))

    state.searchText = "bank"
    #expect(state.categories == ["Personal", "Work"])
    #expect(Set(state.items.map(\.id)) == Set([bankWork.id, bankPersonal.id]))

    state.selectCategory("Work")
    #expect(state.selectedCategory == "Work")
    #expect(state.items.map(\.id) == [bankWork.id])

    state.selectCategory(nil)
    #expect(state.selectedCategory == nil)
    #expect(Set(state.items.map(\.id)) == Set([bankWork.id, bankPersonal.id]))
}

@MainActor
@Test("category list refreshes after creating editing and deleting logins")
func categoryListRefreshesAfterLibraryMutations() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let session = VaultSession(directory: directory)
    try session.create(masterPassword: "correct horse battery staple")
    let initial = loginItem(title: "Home", category: "Personal")
    try session.loginItemRepository().create(initial)
    let state = VaultAppState(session: session)

    state.searchText = ""
    state.addItem(title: "Payroll", username: "ada", password: "secret", url: "", category: "Work", note: "")
    #expect(state.categories == ["Personal", "Work"])

    state.editSelectedItem(
        title: "Payroll", username: "ada", password: "secret", url: "", category: "Travel", note: ""
    )
    #expect(state.categories == ["Personal", "Travel"])

    state.deleteSelectedItem()
    #expect(state.categories == ["Personal"])
}

private final class ManualAppScheduler: ClipboardScheduler, VaultLockScheduler {
    private var actions: [() -> Void] = []
    private(set) var delays: [TimeInterval] = []

    func schedule(after delay: TimeInterval, action: @escaping () -> Void) {
        delays.append(delay)
        actions.append(action)
    }

    func fireFirst() {
        actions.first?()
    }

    func fireLast() {
        actions.last?()
    }

    func fireFirst(after delay: TimeInterval) {
        guard let index = delays.firstIndex(of: delay) else { return }
        actions[index]()
    }
}

private func loginItem(title: String, category: String) -> LoginItem {
    LoginItem(
        id: UUID(), title: title, username: "ada", password: "secret", url: "",
        category: category, note: "", createdAt: .now, updatedAt: .now, revision: 0, deviceID: UUID()
    )
}

private final class RecordingClipboard: Clipboard {
    private(set) var changeCount = 0
    private(set) var writeCount = 0
    private(set) var text: String?

    func write(_ text: String) {
        writeCount += 1
        self.text = text
        changeCount += 1
    }

    func clear() {
        text = nil
        changeCount += 1
    }
}

private final class ManualClipboardClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }

    func advance(by interval: TimeInterval) {
        now.addTimeInterval(interval)
    }
}

private final class ManualUnlockClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }

    func advance(by interval: TimeInterval) {
        now.addTimeInterval(interval)
    }
}
