import Foundation
import Testing

@Test("clipboard status keeps its message and action in a compact leading-aligned container")
func clipboardStatusUsesCompactLeadingAlignedLayout() throws {
    let testFile = URL(filePath: #filePath)
    let packageDirectory = testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = packageDirectory.appending(path: "Sources/PwdlockMacApp/VaultViews.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)

    #expect(source.contains("ClipboardStatusView("))

    let componentStart = try #require(source.range(of: "private struct ClipboardStatusView: View"))
    let followingViewStart = try #require(
        source.range(of: "private struct NewLoginItemView: View", range: componentStart.upperBound..<source.endIndex)
    )
    let component = String(source[componentStart.lowerBound..<followingViewStart.lowerBound])

    #expect(component.contains("VStack(alignment: .leading"))
    #expect(component.contains("HStack(spacing: 8)"))
    #expect(component.contains("密码已复制，将在 \\(clipboardSecondsRemaining) 秒后清除"))
    #expect(component.contains("Button(\"清除剪贴板\", action: clearCopiedPassword)"))
    #expect(!component.contains("Spacer()"))
}

@Test("first-run and library views expose the encrypted archive import and export flows")
func archiveTransferViewsUseChineseLabelsWithoutDisplayingPathsOrSecrets() throws {
    let testFile = URL(filePath: #filePath)
    let packageDirectory = testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let source = try String(
        contentsOf: packageDirectory.appending(path: "Sources/PwdlockMacApp/VaultViews.swift"),
        encoding: .utf8
    )

    #expect(source.contains("Button(\"从加密文件导入\")"))
    #expect(source.contains("private struct ImportArchiveView: View"))
    #expect(source.contains("选择加密文件"))
    #expect(source.contains("导出密码"))
    #expect(source.contains("新的本地主密码"))
    #expect(source.contains("忘记主密码将无法恢复。"))
    #expect(source.contains("Button(\"导出密码库\""))
    #expect(source.contains("private struct ExportArchiveView: View"))
    #expect(source.contains("不要重复使用主密码。"))
}

@Test("library exposes import and conflict center while conflict passwords stay masked")
func importConflictUIContract() throws {
    let testFile = URL(filePath: #filePath)
    let packageDirectory = testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let source = try String(
        contentsOf: packageDirectory.appending(path: "Sources/PwdlockMacApp/VaultViews.swift"),
        encoding: .utf8
    )

    #expect(source.contains("导入加密文件"))
    #expect(source.contains("导入不会静默覆盖本地记录"))
    #expect(source.contains("待处理冲突"))
    #expect(source.contains("使用导入版本"))
    #expect(source.contains("保留本地版本"))
    #expect(source.contains("采用导入"))
    #expect(source.contains("String(repeating: \"•\""))
    #expect(source.contains("if state.mergeManually("))
    #expect(source.contains("@State private var expectedLocal: LoginItem"))
    #expect(source.contains("expectedLocal: expectedLocal"))
}

@Test("Touch ID controls preserve the master-password unlock path")
func touchIDUIContract() throws {
    let testFile = URL(filePath: #filePath)
    let packageDirectory = testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let source = try String(
        contentsOf: packageDirectory.appending(path: "Sources/PwdlockMacApp/VaultViews.swift"),
        encoding: .utf8
    )

    #expect(source.contains("使用 Touch ID 解锁"))
    #expect(source.contains("启用 Touch ID 快捷解锁"))
    #expect(source.contains("SecureField(\"主密码\""))
    #expect(source.contains("Button(\"解锁\""))
    #expect(!source.contains(".navigationTitle(\"密码锁\")"))
    #expect(!source.contains("Button(\"创建本地备份\""))
    #expect(!source.contains("Button(\"恢复最新备份\""))
    #expect(source.contains("Section(\"搜索\")"))
    #expect(source.contains("TextField(\"搜索标题、用户名、网站、分类或备注\""))
    #expect(!source.contains("Picker(\"分类\""))
    #expect(!source.contains("state.beginUnlockScreenIfNeeded()"))
    #expect(source.contains("systemImage: \"touchid\""))

    let appSource = try String(
        contentsOf: packageDirectory.appending(path: "Sources/PwdlockMacApp/PwdlockMacApp.swift"),
        encoding: .utf8
    )
    #expect(appSource.contains("@NSApplicationDelegateAdaptor"))
    #expect(appSource.contains("applicationDidResignActive"))
    #expect(appSource.contains("state.applicationDidResignActive()"))
}

@Test("local login detail uses the same structured dark card as the online password library")
func localLoginDetailLayoutContract() throws {
    let testFile = URL(filePath: #filePath)
    let packageDirectory = testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let source = try String(
        contentsOf: packageDirectory.appending(path: "Sources/PwdlockMacApp/VaultViews.swift"),
        encoding: .utf8
    )

    let componentStart = try #require(source.range(of: "private struct LoginDetailView: View"))
    let followingViewStart = try #require(
        source.range(of: "private struct ClipboardStatusView: View", range: componentStart.upperBound..<source.endIndex)
    )
    let component = String(source[componentStart.lowerBound..<followingViewStart.lowerBound])

    #expect(component.contains("OnlineDetailRow(\"用户名\")"))
    #expect(component.contains(".truncationMode(.middle)"))
    #expect(component.contains(".background(Color.black.opacity(0.16))"))
    #expect(component.contains("ClipboardStatusView("))
    #expect(component.contains("Button(\"打开网站\", systemImage: \"arrow.up.right.square\""))
}
