import Foundation
@preconcurrency import LocalAuthentication
import PwdlockCore

enum VaultScreen: Equatable {
    case create
    case unlock
    case library
}

enum AutoLockDuration: Int, CaseIterable, Equatable, Identifiable {
    case threeMinutes = 180
    case fiveMinutes = 300
    case tenMinutes = 600

    static let defaultsKey = "autoLockDuration"

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) }
    var title: String { "\(rawValue / 60) 分钟" }
}

@MainActor
final class VaultAppState: ObservableObject {
    @Published private(set) var screen: VaultScreen
    @Published private(set) var items: [LoginItem] = []
    @Published var searchText = "" {
        didSet {
            reloadItems()
            recordActivity()
        }
    }
    @Published private(set) var selectedItem: LoginItem?
    @Published private(set) var selectedCategory: String?
    @Published private(set) var categories: [String] = []
    @Published private(set) var autoLockDuration: AutoLockDuration
    @Published private(set) var errorMessage: String?
    @Published private(set) var operationSummary: String?
    @Published private(set) var isPasswordRevealed = false
    @Published private(set) var clipboardSecondsRemaining: Int?
    @Published var isChangeMasterPasswordPresented = false
    @Published var isExportArchivePresented = false
    @Published var isExistingVaultImportPresented = false
    @Published var isConflictCenterPresented = false
    @Published private(set) var pendingConflicts: [ImportConflict] = []
    @Published private(set) var canUseTouchID = false
    @Published private(set) var isTouchIDEnabled = false
    @Published private(set) var isTouchIDAuthenticating = false

    var pendingConflictCount: Int { pendingConflicts.count }
    var isTouchIDAvailable: Bool { biometricAuthenticator.isTouchIDAvailable }

    private let session: VaultSession
    private var autoLockController: VaultAutoLockController? = nil
    private let clipboardService: PasswordClipboardService
    private let clipboardScheduler: any ClipboardScheduler
    private let now: () -> Date
    private var clipboardExpiry: Date?
    private let unlockRateLimiter: UnlockRateLimiter
    private let userDefaults: UserDefaults
    private let biometricAuthenticator: any BiometricAuthenticating
    private var allItems: [LoginItem] = []
    private var didAutomaticallyPromptTouchID = false
    private var touchIDAttemptID: UUID?

    convenience init(directory: URL = VaultAppState.defaultVaultDirectory()) {
        self.init(session: VaultSession(directory: directory))
    }

    convenience init(session: VaultSession) {
        self.init(session: session, scheduler: MainQueueScheduler())
    }

    convenience init<S: ClipboardScheduler & VaultLockScheduler>(session: VaultSession, scheduler: S) {
        self.init(session: session, scheduler: scheduler, clipboard: PasteboardClipboard())
    }

    init<S: ClipboardScheduler & VaultLockScheduler, C: Clipboard>(
        session: VaultSession,
        scheduler: S,
        clipboard: C,
        biometricAuthenticator: any BiometricAuthenticating = LocalAuthenticationAuthenticator(),
        unlockRateLimiter: UnlockRateLimiter = UnlockRateLimiter(),
        userDefaults: UserDefaults = .standard,
        now: @escaping () -> Date = { Date() }
    ) {
        self.session = session
        clipboardService = PasswordClipboardService(clipboard: clipboard, scheduler: scheduler)
        clipboardScheduler = scheduler
        self.now = now
        self.unlockRateLimiter = unlockRateLimiter
        self.userDefaults = userDefaults
        self.biometricAuthenticator = biometricAuthenticator
        let storedValue = userDefaults.object(forKey: AutoLockDuration.defaultsKey)
        let storedTimeout = storedValue as? Int
        autoLockDuration = AutoLockDuration(rawValue: storedTimeout ?? AutoLockDuration.fiveMinutes.rawValue)
            ?? .fiveMinutes
        if storedValue == nil {
            userDefaults.set(AutoLockDuration.fiveMinutes.rawValue, forKey: AutoLockDuration.defaultsKey)
        }
        let metadataURL = session.directory.appendingPathComponent("vault.meta", isDirectory: false)
        if session.isUnlocked {
            screen = .library
        } else {
            screen = FileManager.default.fileExists(atPath: metadataURL.path) ? .unlock : .create
        }
        autoLockController = VaultAutoLockController(session: session, scheduler: scheduler, timeout: autoLockDuration.seconds) { [weak self] in
            self?.resetLockedState()
        }
        if session.isUnlocked {
            reloadItems()
            reloadConflicts()
        }
        refreshTouchIDState()
    }

    func createVault(masterPassword: String, confirmation: String) {
        guard masterPassword == confirmation else {
            errorMessage = "密码不一致。"
            return
        }
        guard MasterPasswordPolicy.isValid(masterPassword) else {
            errorMessage = "主密码至少需要 12 个字符。"
            return
        }

        do {
            try session.create(masterPassword: masterPassword)
            errorMessage = nil
            screen = .library
            reloadItems()
            reloadConflicts()
            refreshTouchIDState()
            recordActivity()
        } catch {
            errorMessage = "无法创建密码库。"
        }
    }

    /// First-run only: imports an authenticated archive into a newly-created local vault.
    /// The UI keeps all paths and underlying errors private; this helper is file-panel agnostic.
    func importArchive(
        at archiveURL: URL,
        exportPassword: String,
        exportPasswordConfirmation: String,
        newMasterPassword: String,
        newMasterPasswordConfirmation: String
    ) {
        guard screen == .create else {
            errorMessage = "无法导入加密文件。"
            return
        }
        guard exportPassword == exportPasswordConfirmation,
              newMasterPassword == newMasterPasswordConfirmation else {
            errorMessage = "密码不一致。"
            return
        }
        guard MasterPasswordPolicy.isValid(newMasterPassword) else {
            errorMessage = "主密码至少需要 12 个字符。"
            return
        }

        do {
            try session.importArchive(
                at: archiveURL,
                exportPassword: exportPassword,
                newMasterPassword: newMasterPassword
            )
            errorMessage = nil
            operationSummary = "已导入 \(try session.loginItemRepository().search(query: "").count) 个登录项。"
            screen = .library
            reloadItems()
            refreshTouchIDState()
            recordActivity()
        } catch {
            operationSummary = nil
            errorMessage = "无法导入加密文件。"
        }
    }

    func presentExportArchive() {
        isExportArchivePresented = true
        recordActivity()
    }

    func presentExistingVaultImport() {
        isExistingVaultImportPresented = true
        recordActivity()
    }

    func importIntoExistingVault(at archiveURL: URL, exportPassword: String) {
        guard screen == .library, !exportPassword.isEmpty else {
            errorMessage = "密码错误或文件损坏，未修改当前密码库。"
            return
        }
        do {
            let summary = try session.mergeArchive(at: archiveURL, exportPassword: exportPassword)
            operationSummary = "导入完成：新增 \(summary.added) 项，已存在 \(summary.identical) 项，待处理冲突 \(summary.conflicts) 项。"
            errorMessage = nil
            isExistingVaultImportPresented = false
            reloadItems()
            reloadConflicts()
            recordActivity()
        } catch {
            operationSummary = nil
            errorMessage = "密码错误或文件损坏，未修改当前密码库。"
        }
    }

    @discardableResult
    func useImported(conflictID: UUID) -> Bool {
        performConflictAction {
            try session.loginItemRepository().resolveUsingImported(conflictID: conflictID)
        }
    }

    @discardableResult
    func keepLocal(conflictID: UUID) -> Bool {
        performConflictAction {
            try session.loginItemRepository().resolveKeepingLocal(conflictID: conflictID)
        }
    }

    @discardableResult
    func mergeManually(conflictID: UUID, merge: ManualLoginMerge, expectedLocal: LoginItem) -> Bool {
        performConflictAction {
            try session.loginItemRepository().resolveManually(
                conflictID: conflictID,
                merge: merge,
                expectedLocal: expectedLocal
            )
        }
    }

    private func performConflictAction(_ action: () throws -> Void) -> Bool {
        do {
            try action()
            errorMessage = nil
            reloadItems()
            reloadConflicts()
            recordActivity()
            return true
        } catch LoginItemRepositoryError.conflictChanged {
            reloadItems()
            reloadConflicts()
            errorMessage = "本地记录已更新，请重新检查冲突。"
            recordActivity()
            return false
        } catch {
            errorMessage = "无法处理此冲突。"
            return false
        }
    }

    /// Exports using an independent password supplied by the export sheet.
    func exportArchive(to archiveURL: URL, exportPassword: String, confirmation: String) {
        guard !exportPassword.isEmpty, exportPassword == confirmation else {
            errorMessage = "密码不一致。"
            return
        }

        do {
            try session.exportArchive(to: archiveURL, exportPassword: exportPassword)
            errorMessage = nil
            operationSummary = "已导出密码库。"
            isExportArchivePresented = false
            recordActivity()
        } catch {
            errorMessage = "无法导出密码库。"
        }
    }

    func unlock(masterPassword: String) {
        guard !unlockRateLimiter.isCoolingDown else {
            errorMessage = "请稍后再试。"
            return
        }

        do {
            try session.unlock(masterPassword: masterPassword)
            if touchIDAttemptID != nil {
                biometricAuthenticator.cancel()
                touchIDAttemptID = nil
                isTouchIDAuthenticating = false
            }
            unlockRateLimiter.recordSuccessfulUnlock()
            errorMessage = nil
            finishUnlock()
        } catch {
            unlockRateLimiter.recordFailedUnlock()
            errorMessage = "无法解锁密码库。"
        }
    }

    func changeMasterPassword(currentPassword: String, newPassword: String, confirmation: String) {
        guard newPassword == confirmation else {
            errorMessage = "密码不一致。"
            return
        }
        guard MasterPasswordPolicy.isValid(newPassword) else {
            errorMessage = "主密码至少需要 12 个字符。"
            return
        }

        do {
            try session.changeMasterPassword(currentPassword: currentPassword, newPassword: newPassword)
            errorMessage = nil
            refreshTouchIDState()
        } catch {
            errorMessage = "无法更改主密码。"
        }
    }

    func presentChangeMasterPassword() {
        isChangeMasterPasswordPresented = true
        recordActivity()
    }

    func createLocalBackup() {
        do {
            try session.createLocalBackup()
            recordActivity()
        } catch {
            errorMessage = "无法创建本地备份。"
        }
    }

    func restoreLatestLocalBackup() {
        isConflictCenterPresented = false
        pendingConflicts = []
        do {
            try session.restoreLatestLocalBackup()
            selectedItem = nil
            isPasswordRevealed = false
            reloadItems()
            reloadConflicts()
            recordActivity()
        } catch {
            reloadConflicts()
            errorMessage = "无法恢复最新本地备份。"
        }
    }

    func lock() {
        clipboardService.clearNow()
        clearClipboardCountdown()
        session.lock()
        resetLockedState()
    }

    func applicationDidEnterBackground() {
        biometricAuthenticator.cancel()
        touchIDAttemptID = nil
        isTouchIDAuthenticating = false
        autoLockController?.applicationDidEnterBackground()
    }

    func recordActivity() {
        autoLockController?.recordActivity()
    }

    func setAutoLockDuration(_ duration: AutoLockDuration) {
        autoLockDuration = duration
        userDefaults.set(duration.rawValue, forKey: AutoLockDuration.defaultsKey)
        autoLockController?.updateTimeout(duration.seconds)
    }

    func selectCategory(_ category: String?) {
        let normalized = category?.trimmingCharacters(in: .whitespacesAndNewlines)
        selectedCategory = normalized.flatMap { categories.contains($0) ? $0 : nil }
        applyFilters()
        recordActivity()
    }

    func reconcileLockState() {
        guard screen == .library, !session.isUnlocked else { return }
        resetLockedState()
    }

    private func resetLockedState() {
        clipboardService.clearNow()
        clearClipboardCountdown()
        allItems = []
        items = []
        selectedItem = nil
        selectedCategory = nil
        categories = []
        isPasswordRevealed = false
        isChangeMasterPasswordPresented = false
        isExportArchivePresented = false
        isExistingVaultImportPresented = false
        isConflictCenterPresented = false
        pendingConflicts = []
        touchIDAttemptID = nil
        isTouchIDAuthenticating = false
        didAutomaticallyPromptTouchID = false
        screen = .unlock
        refreshTouchIDState()
    }

    func beginUnlockScreenIfNeeded() {
        refreshTouchIDState()
        guard screen == .unlock,
              canUseTouchID,
              !didAutomaticallyPromptTouchID,
              !isTouchIDAuthenticating else { return }
        didAutomaticallyPromptTouchID = true
        requestTouchIDUnlock()
    }

    func retryTouchID() {
        refreshTouchIDState()
        guard screen == .unlock, canUseTouchID, !isTouchIDAuthenticating else { return }
        requestTouchIDUnlock()
    }

    func setTouchIDEnabled(_ enabled: Bool) {
        guard screen == .library else { return }
        do {
            if enabled {
                try session.enableBiometricUnlock()
            } else {
                try session.disableBiometricUnlock()
            }
            errorMessage = nil
        } catch VaultSessionError.masterPasswordUnlockRequired {
            errorMessage = "请先使用主密码解锁后再启用 Touch ID。"
        } catch {
            errorMessage = enabled ? "无法启用 Touch ID 快捷解锁。" : "无法关闭 Touch ID 快捷解锁。"
        }
        refreshTouchIDState()
        recordActivity()
    }

    private func requestTouchIDUnlock() {
        let attemptID = UUID()
        touchIDAttemptID = attemptID
        isTouchIDAuthenticating = true
        biometricAuthenticator.authenticate(reason: "使用 Touch ID 解锁密码库") { [weak self] result, context in
            Task { @MainActor [weak self] in
                self?.finishTouchIDAttempt(id: attemptID, result: result, context: context)
            }
        }
    }

    private func finishTouchIDAttempt(
        id: UUID,
        result: BiometricAuthenticationResult,
        context: BiometricAuthenticationContext?
    ) {
        guard touchIDAttemptID == id else { return }
        touchIDAttemptID = nil
        isTouchIDAuthenticating = false
        switch result {
        case .cancelled:
            return
        case .failed:
            errorMessage = "Touch ID 无法完成验证，请使用主密码。"
        case .success:
            do {
                try session.unlockWithBiometrics(context: context?.localAuthenticationContext)
                errorMessage = nil
                finishUnlock()
            } catch {
                errorMessage = "Touch ID 无法完成验证，请使用主密码。"
                refreshTouchIDState()
            }
        }
    }

    private func finishUnlock() {
        screen = .library
        reloadItems()
        reloadConflicts()
        refreshTouchIDState()
        recordActivity()
    }

    private func refreshTouchIDState() {
        isTouchIDEnabled = session.isBiometricUnlockConfigured
        canUseTouchID = screen == .unlock
            && biometricAuthenticator.isTouchIDAvailable
            && isTouchIDEnabled
    }

    func selectItem(id: UUID?) {
        guard let id else {
            selectedItem = nil
            isPasswordRevealed = false
            return
        }

        do {
            selectedItem = try session.loginItemRepository().item(id: id)
            isPasswordRevealed = false
            recordActivity()
        } catch {
            errorMessage = "无法载入密码条目。"
        }
    }

    func addItem(title: String, username: String, password: String, url: String, category: String, note: String) {
        let now = Date()
        let item = LoginItem(
            id: UUID(), title: title, username: username, password: password, url: url,
            category: category, note: note, createdAt: now, updatedAt: now,
            revision: 0, deviceID: UUID()
        )

        do {
            try session.loginItemRepository().create(item)
            reloadItems()
            selectItem(id: item.id)
            recordActivity()
        } catch {
            errorMessage = "无法保存密码条目。"
        }
    }

    func editSelectedItem(
        title: String,
        username: String,
        password: String,
        url: String,
        category: String,
        note: String
    ) {
        guard let selectedItem else { return }

        let updatedItem = LoginItem(
            id: selectedItem.id,
            title: title,
            username: username,
            password: password,
            url: url,
            category: category,
            note: note,
            createdAt: selectedItem.createdAt,
            updatedAt: Date(),
            revision: selectedItem.revision + 1,
            deviceID: selectedItem.deviceID
        )

        do {
            let repository = try session.loginItemRepository()
            try repository.update(updatedItem)
            reloadItems()
            self.selectedItem = try repository.item(id: updatedItem.id)
            isPasswordRevealed = false
            recordActivity()
        } catch {
            errorMessage = "无法更新密码条目。"
        }
    }

    func deleteSelectedItem() {
        guard let selectedItem else { return }

        do {
            try session.loginItemRepository().delete(id: selectedItem.id)
            self.selectedItem = nil
            isPasswordRevealed = false
            reloadItems()
            recordActivity()
        } catch {
            errorMessage = "无法删除密码条目。"
        }
    }

    func togglePasswordReveal() {
        isPasswordRevealed.toggle()
        recordActivity()
    }

    @discardableResult
    func copySelectedPassword() -> Bool {
        guard let selectedItem else { return false }
        clipboardService.copy(password: selectedItem.password)
        startClipboardCountdown()
        recordActivity()
        return true
    }

    func clearCopiedPassword() {
        clipboardService.clearNow()
        clearClipboardCountdown()
        recordActivity()
    }

    func dismissError() {
        errorMessage = nil
    }

    private func reloadItems() {
        guard session.isUnlocked else { return }
        do {
            allItems = try session.loginItemRepository().search(query: "")
            applyFilters()
        } catch {
            errorMessage = "无法载入密码条目。"
        }
    }

    private func reloadConflicts() {
        guard session.isUnlocked else { return }
        do {
            pendingConflicts = try session.loginItemRepository().pendingConflicts()
        } catch {
            pendingConflicts = []
            errorMessage = "无法载入待处理冲突。"
        }
    }

    private func applyFilters() {
        categories = Array(Set(allItems.map { $0.category.trimmingCharacters(in: .whitespacesAndNewlines) }))
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        if let selectedCategory, !categories.contains(selectedCategory) {
            self.selectedCategory = nil
        }

        items = allItems.filter { item in
            let titleMatches = searchText.isEmpty || item.title.localizedCaseInsensitiveContains(searchText)
            let categoryMatches = selectedCategory == nil
                || item.category.trimmingCharacters(in: .whitespacesAndNewlines) == selectedCategory
            return titleMatches && categoryMatches
        }
    }

    private func startClipboardCountdown() {
        let expiry = now().addingTimeInterval(PasswordClipboardService.automaticClearDelay)
        clipboardExpiry = expiry
        clipboardSecondsRemaining = Int(PasswordClipboardService.automaticClearDelay)
        scheduleClipboardCountdownUpdate(for: expiry)
    }

    private func scheduleClipboardCountdownUpdate(for expiry: Date) {
        clipboardScheduler.schedule(after: 1) { [weak self] in
            self?.updateClipboardCountdown(expectedExpiry: expiry)
        }
    }

    private func updateClipboardCountdown(expectedExpiry: Date) {
        guard clipboardExpiry == expectedExpiry else { return }
        let remaining = max(0, Int(ceil(expectedExpiry.timeIntervalSince(now()))))
        guard remaining > 0 else {
            clearClipboardCountdown()
            return
        }
        clipboardSecondsRemaining = remaining
        scheduleClipboardCountdownUpdate(for: expectedExpiry)
    }

    private func clearClipboardCountdown() {
        clipboardExpiry = nil
        clipboardSecondsRemaining = nil
    }

    private static func defaultVaultDirectory() -> URL {
        let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return supportDirectory.appendingPathComponent("Pwdlock", isDirectory: true)
    }
}
