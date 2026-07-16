import Foundation
import Testing

@Test("entry view separates local and online password-library modes")
func passwordModeEntryViewContract() throws {
    let packageDirectory = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let appSource = try String(contentsOf: packageDirectory.appending(path: "Sources/PwdlockMacApp/PwdlockMacApp.swift"), encoding: .utf8)
    let viewsSource = try String(contentsOf: packageDirectory.appending(path: "Sources/PwdlockMacApp/VaultViews.swift"), encoding: .utf8)

    #expect(appSource.contains("enum PasswordStorageMode"))
    #expect(appSource.contains("PasswordModeSelectionView"))
    #expect(appSource.contains("OnlineVaultRootView"))
    #expect(viewsSource.contains("本地密码库"))
    #expect(viewsSource.contains("在线密码库"))
    #expect(viewsSource.contains("密码条目始终在本机加密和解密；服务端只保存密文。"))
}

@Test("online sign out requires confirmation in both locked and unlocked views")
func onlineSignOutConfirmationContract() throws {
    let packageDirectory = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let viewsSource = try String(
        contentsOf: packageDirectory.appending(path: "Sources/PwdlockMacApp/VaultViews.swift"),
        encoding: .utf8
    )

    #expect(viewsSource.contains("@State private var showingSignOutConfirmation = false"))
    #expect(viewsSource.contains("confirmationDialog(\"退出在线账号？\""))
    #expect(viewsSource.contains("退出后将锁定在线密码库，并清除这台 Mac 上的登录状态。"))
    #expect(viewsSource.contains("showingSignOutConfirmation = true"))
}
