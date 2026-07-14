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
