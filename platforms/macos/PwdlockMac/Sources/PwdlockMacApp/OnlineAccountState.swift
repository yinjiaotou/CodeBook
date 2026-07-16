import Foundation
import Security
import SwiftUI
import PwdlockCore

@MainActor
final class OnlineAccountState: ObservableObject {
    @Published var loginName = ""
    @Published var password = ""
    @Published private(set) var isWorking = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var onlineVaultCreated = false
    @Published private(set) var onlineVaults: [OnlineVault] = []
    @Published private(set) var isOnlineVaultUnlocked = false
    @Published private(set) var isSignedIn = false
    private let serviceURL = URL(string: "http://127.0.0.1:3000/v1")!
    private static let service = "com.pwdlock.mac.online-access-token"

    func login() { authenticate(register: false) }
    func register() { authenticate(register: true) }
    func signOut() { deleteToken(); password = ""; isSignedIn = false }
    func unlockOnlineVault(masterPassword: String) {
        guard let vault = onlineVaults.first, !isWorking else { return }
        isWorking = true; errorMessage = nil
        do {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Pwdlock/OnlineCache", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let database = try OnlineVaultAccess.openCache(
                at: directory.appendingPathComponent("\(vault.id.uuidString.lowercased()).sqlite"),
                encryptedKeyEnvelope: vault.encryptedKeyEnvelope,
                masterPassword: masterPassword
            )
            database.close()
            isOnlineVaultUnlocked = true
        } catch { errorMessage = "无法解锁在线密码库。" }
        isWorking = false
    }
    func createOnlineVault(masterPassword: String) {
        guard let token = accessToken(), !isWorking else { errorMessage = "登录状态已失效。"; return }
        let account = loginName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !account.isEmpty else { errorMessage = "无法识别当前账号。"; return }
        isWorking = true; errorMessage = nil
        Task {
            let keyStore = OnlineDeviceKeyStore()
            do {
                let created = try OnlineVaultBootstrap.create(masterPassword: masterPassword)
                try keyStore.save(created.deviceSigningKey, accountID: account)
                let api = OnlineAPIClient(baseURL: serviceURL)
                _ = try await api.registerDevice(label: Host.current().localizedName ?? "Mac", publicSigningKey: created.publicSigningKey, accessToken: token)
                _ = try await api.createVault(encryptedKeyEnvelope: created.encryptedKeyEnvelope, accessToken: token)
                onlineVaults = try await api.listVaults(accessToken: token)
                onlineVaultCreated = !onlineVaults.isEmpty
            } catch {
                keyStore.delete(accountID: account)
                errorMessage = "无法创建在线密码库。"
            }
            isWorking = false
        }
    }
    func accessToken() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service, kSecAttrAccount as String: "current", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func authenticate(register: Bool) {
        let account = loginName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !account.isEmpty, !password.isEmpty else {
            errorMessage = "请输入账号和账户密码。"
            return
        }
        guard !register || password.count >= 12 else {
            errorMessage = "账户密码至少需要 12 个字符。"
            return
        }
        guard !isWorking else { return }
        isWorking = true; errorMessage = nil
        Task {
            do {
                let api = OnlineAPIClient(baseURL: serviceURL)
                let session = try await (register ? api.register(loginName: account, password: password) : api.login(loginName: account, password: password))
                try saveToken(session.accessToken); password = ""; isSignedIn = true
                onlineVaults = try await api.listVaults(accessToken: session.accessToken)
                onlineVaultCreated = !onlineVaults.isEmpty
            } catch { errorMessage = register ? "无法创建在线账号。" : "账号或密码错误，或无法连接服务。" }
            isWorking = false
        }
    }
    private func saveToken(_ token: String) throws {
        deleteToken()
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service, kSecAttrAccount as String: "current", kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly, kSecValueData as String: Data(token.utf8)]
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw OnlineAPIError.transportFailed }
    }
    private func deleteToken() { SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service, kSecAttrAccount as String: "current"] as CFDictionary) }
}
