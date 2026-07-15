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
