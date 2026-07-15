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
    @Published private(set) var isSignedIn = false
    private let serviceURL = URL(string: "http://127.0.0.1:3000/v1")!
    private static let service = "com.pwdlock.mac.online-access-token"

    func login() { authenticate(register: false) }
    func register() { authenticate(register: true) }
    func signOut() { deleteToken(); password = ""; isSignedIn = false }
    func accessToken() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service, kSecAttrAccount as String: "current", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func authenticate(register: Bool) {
        let account = loginName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !account.isEmpty, !password.isEmpty, !isWorking else { return }
        isWorking = true; errorMessage = nil
        Task {
            do {
                let api = OnlineAPIClient(baseURL: serviceURL)
                let session = try await (register ? api.register(loginName: account, password: password) : api.login(loginName: account, password: password))
                try saveToken(session.accessToken); password = ""; isSignedIn = true
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
