import AppKit
import CryptoKit
import Foundation
import PwdlockCore

/// State for the online vault after its client-side key envelope has been unlocked.
/// The SQLCipher cache is always opened locally; sync requests only carry sealed changes.
@MainActor
final class OnlineVaultLibraryState: ObservableObject {
    @Published private(set) var items: [LoginItem] = []
    @Published private(set) var selectedItem: LoginItem?
    @Published var searchText = "" { didSet { reloadItems() } }
    @Published private(set) var isWorking = false
    @Published private(set) var isDeviceReady = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?

    let vaultID: UUID
    private let accountID: String
    private let accessToken: String
    private let api: OnlineAPIClient
    private let vaultKey: Data
    private let database: EncryptedDatabase
    private let repository: LoginItemRepository
    private let keyStore = OnlineDeviceKeyStore()
    private var signingKey: Curve25519.Signing.PrivateKey?
    private var deviceID: UUID?

    static func open(
        vault: OnlineVault,
        masterPassword: String,
        accountID: String,
        accessToken: String,
        serviceURL: URL
    ) throws -> OnlineVaultLibraryState {
        let vaultKey = try OnlineVaultAccess.unlockKey(
            encryptedKeyEnvelope: vault.encryptedKeyEnvelope,
            masterPassword: masterPassword
        )
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pwdlock/OnlineCache", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try EncryptedDatabase.open(
            at: directory.appendingPathComponent("\(vault.id.uuidString.lowercased()).sqlite"),
            vaultKey: vaultKey
        )
        do {
            let repository = LoginItemRepository(database: database)
            try repository.migrate()
            return OnlineVaultLibraryState(
                vaultID: vault.id,
                accountID: accountID,
                accessToken: accessToken,
                api: OnlineAPIClient(baseURL: serviceURL),
                vaultKey: vaultKey,
                database: database,
                repository: repository
            )
        } catch {
            database.close()
            throw error
        }
    }

    private init(
        vaultID: UUID,
        accountID: String,
        accessToken: String,
        api: OnlineAPIClient,
        vaultKey: Data,
        database: EncryptedDatabase,
        repository: LoginItemRepository
    ) {
        self.vaultID = vaultID
        self.accountID = accountID
        self.accessToken = accessToken
        self.api = api
        self.vaultKey = vaultKey
        self.database = database
        self.repository = repository
        reloadItems()
        Task { await configureDevice() }
    }

    deinit { database.close() }

    func close() { database.close() }

    func selectItem(id: UUID?) {
        selectedItem = id.flatMap { candidate in items.first { $0.id == candidate } }
    }

    func dismissError() { errorMessage = nil }

    func copyPassword(_ item: LoginItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.password, forType: .string)
        statusMessage = "密码已复制到剪贴板。"
    }

    func synchronize() {
        guard isDeviceReady, !isWorking else { return }
        Task { await downloadChanges() }
    }

    func addItem(title: String, username: String, password: String, url: String, category: String, note: String) {
        guard let deviceID else { errorMessage = "正在准备此设备，请稍后重试。"; return }
        let now = Date()
        let item = LoginItem(
            id: UUID(), title: title, username: username, password: password, url: url,
            category: category, note: note, createdAt: now, updatedAt: now, revision: 0, deviceID: deviceID
        )
        uploadAndApply(operation: .upsert, item: item)
    }

    func editSelectedItem(title: String, username: String, password: String, url: String, category: String, note: String) {
        guard let selectedItem else { return }
        let item = LoginItem(
            id: selectedItem.id, title: title, username: username, password: password, url: url,
            category: category, note: note, createdAt: selectedItem.createdAt, updatedAt: Date(),
            revision: selectedItem.revision + 1, deviceID: selectedItem.deviceID
        )
        uploadAndApply(operation: .upsert, item: item)
    }

    func deleteSelectedItem() {
        guard let selectedItem else { return }
        uploadAndApply(operation: .delete, item: selectedItem)
    }

    private func configureDevice() async {
        do {
            let key: Curve25519.Signing.PrivateKey
            if let stored = try keyStore.read(accountID: accountID) {
                key = stored
            } else {
                key = Curve25519.Signing.PrivateKey()
                try keyStore.save(key, accountID: accountID)
            }
            signingKey = key
            let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
            let devices = try await api.listDevices(accessToken: accessToken)
            if let existing = devices.first(where: { $0.publicSigningKey == publicKey }) {
                deviceID = existing.id
            } else {
                deviceID = try await api.registerDevice(
                    label: Host.current().localizedName ?? "Mac",
                    publicSigningKey: publicKey,
                    accessToken: accessToken
                ).id
            }
            isDeviceReady = true
            statusMessage = "此设备已准备就绪。"
        } catch {
            errorMessage = "无法准备同步设备，请检查网络后重试。"
        }
    }

    private func uploadAndApply(operation: OnlineVaultChange.Operation, item: LoginItem) {
        guard let signingKey, let deviceID, !isWorking else {
            errorMessage = "正在准备此设备，请稍后重试。"
            return
        }
        isWorking = true
        errorMessage = nil
        Task {
            do {
                let changeID = UUID()
                let change = OnlineVaultChange(operation: operation, item: item)
                let envelope = try OnlineVaultChangeCodec.seal(
                    change, vaultID: vaultID, changeID: changeID, vaultKey: vaultKey, signingKey: signingKey
                )
                let remote = try await api.appendChange(
                    vaultID: vaultID, changeID: changeID, deviceID: deviceID, envelope: envelope, accessToken: accessToken
                )
                switch operation {
                case .upsert:
                    if try repository.item(id: item.id) == nil { try repository.create(item) }
                    else { try repository.update(item) }
                    selectedItem = item
                case .delete:
                    try repository.delete(id: item.id)
                    selectedItem = nil
                }
                try OnlineSyncCursorStore.save(remote.sequence, vaultID: vaultID, in: database)
                reloadItems()
                statusMessage = operation == .upsert ? "已加密保存并同步。" : "已删除并同步。"
            } catch {
                errorMessage = "无法同步本次修改，当前条目未改变。"
            }
            isWorking = false
        }
    }

    private func downloadChanges() async {
        isWorking = true
        errorMessage = nil
        do {
            let devices = try await api.listDevices(accessToken: accessToken)
            let publicKeys = try Dictionary(uniqueKeysWithValues: devices.map { device in
                guard let raw = Data(base64Encoded: device.publicSigningKey) else { throw OnlineSyncEnvelopeError.authenticationFailed }
                return (device.id, try Curve25519.Signing.PublicKey(rawRepresentation: raw))
            })
            let cursor = try OnlineSyncCursorStore.cursor(in: database, vaultID: vaultID)
            let changes = try await api.listChanges(vaultID: vaultID, after: cursor, accessToken: accessToken)
            for remote in changes {
                guard let publicKey = publicKeys[remote.deviceId] else { throw OnlineSyncEnvelopeError.authenticationFailed }
                let change = try OnlineVaultChangeCodec.open(remote, vaultID: vaultID, vaultKey: vaultKey, publicSigningKey: publicKey)
                try applyRemote(change, sourceDeviceID: remote.deviceId)
                try OnlineSyncCursorStore.save(remote.sequence, vaultID: vaultID, in: database)
            }
            reloadItems()
            statusMessage = changes.isEmpty ? "已是最新状态。" : "已同步 \(changes.count) 项变更。"
        } catch {
            errorMessage = "同步失败，已保留本机加密缓存。"
        }
        isWorking = false
    }

    private func applyRemote(_ change: OnlineVaultChange, sourceDeviceID: UUID) throws {
        switch change.operation {
        case .delete:
            if try repository.item(id: change.item.id) != nil { try repository.delete(id: change.item.id) }
        case .upsert:
            guard let local = try repository.item(id: change.item.id) else {
                try repository.create(change.item)
                return
            }
            guard !equivalent(local, change.item) else { return }
            _ = try repository.mergeImportedItems(
                [change.item],
                importedSourceVaultID: sourceDeviceID,
                localSourceVaultID: vaultID
            )
        }
    }

    private func reloadItems() {
        do {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let source = try repository.search(query: "")
            items = query.isEmpty ? source : source.filter { item in
                [item.title, item.username, item.url, item.category, item.note]
                    .contains { $0.localizedCaseInsensitiveContains(query) }
            }
            if let selectedItem, !items.contains(where: { $0.id == selectedItem.id }) {
                self.selectedItem = nil
            }
        } catch {
            errorMessage = "无法读取本机加密缓存。"
        }
    }

    private func equivalent(_ lhs: LoginItem, _ rhs: LoginItem) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.username == rhs.username
            && lhs.password == rhs.password && lhs.url == rhs.url && lhs.category == rhs.category
            && lhs.note == rhs.note && lhs.createdAt == rhs.createdAt && lhs.updatedAt == rhs.updatedAt
            && lhs.revision == rhs.revision && lhs.deviceID == rhs.deviceID
    }
}
