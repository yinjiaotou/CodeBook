import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PwdlockCore

struct VaultRootView: View {
    @ObservedObject var state: VaultAppState

    var body: some View {
        Group {
            switch state.screen {
            case .create:
                CreateVaultView(state: state)
            case .unlock:
                UnlockVaultView(state: state)
            case .library:
                VaultLibraryView(state: state)
            }
        }
        .alert("密码锁", isPresented: errorIsPresented) {
            Button("确定", role: .cancel) { state.dismissError() }
        } message: {
            Text(state.errorMessage ?? "")
        }
        .overlay(alignment: .top) {
            if let summary = state.operationSummary, state.screen == .library {
                Text(summary)
                    .font(.footnote)
                    .padding(8)
                    .background(.regularMaterial, in: Capsule())
                    .padding()
            }
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(get: { state.errorMessage != nil }, set: { if !$0 { state.dismissError() } })
    }
}

private struct CreateVaultView: View {
    @ObservedObject var state: VaultAppState
    @State private var password = ""
    @State private var confirmation = ""
    @State private var showingArchiveImport = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 42))
            Text("创建密码库").font(.title2)
            SecureField("主密码", text: $password)
            SecureField("确认主密码", text: $confirmation)
            Text("至少使用 12 个字符。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("忘记主密码将无法恢复。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("创建密码库") {
                state.createVault(masterPassword: password, confirmation: confirmation)
                password = ""
                confirmation = ""
            }
            .buttonStyle(.borderedProminent)
            .disabled(password != confirmation || !MasterPasswordPolicy.isValid(password))
            Button("从加密文件导入") { showingArchiveImport = true }
        }
        .frame(width: 320)
        .padding(36)
        .sheet(isPresented: $showingArchiveImport) { ImportArchiveView(state: state) }
    }
}

private struct UnlockVaultView: View {
    @ObservedObject var state: VaultAppState
    @State private var password = ""

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock")
                .font(.system(size: 42))
            Text("解锁密码库").font(.title2)
            SecureField("主密码", text: $password)
                .onSubmit(unlock)
            Button("解锁", action: unlock)
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty)
        }
        .frame(width: 320)
        .padding(36)
    }

    private func unlock() {
        state.unlock(masterPassword: password)
        password = ""
    }
}

private struct VaultLibraryView: View {
    @ObservedObject var state: VaultAppState
    @State private var selectedID: UUID?
    @State private var showingNewItem = false
    @State private var showingDeleteConfirmation = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedID) {
                Section("分类") {
                    Picker("分类", selection: selectedCategoryBinding) {
                        Text("所有分类").tag(nil as String?)
                        ForEach(state.categories, id: \.self) { category in
                            Text(category).tag(Optional(category))
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("登录信息") {
                    ForEach(state.items, id: \.id) { item in
                        Text(item.title).tag(item.id)
                    }
                }
            }
            .searchable(text: $state.searchText, prompt: "搜索标题")
            .navigationTitle("密码锁")
            .toolbar {
                ToolbarItemGroup {
                    Button { showingNewItem = true } label: { Label("新建登录信息", systemImage: "plus") }
                    Button("创建本地备份", systemImage: "externaldrive.badge.plus") { state.createLocalBackup() }
                    Button("恢复最新备份", systemImage: "arrow.clockwise") { state.restoreLatestLocalBackup() }
                    Button("导入加密文件", systemImage: "square.and.arrow.down") { state.presentExistingVaultImport() }
                    Button("导出密码库", systemImage: "square.and.arrow.up") { state.presentExportArchive() }
                    Button {
                        state.isConflictCenterPresented = true
                    } label: {
                        Label("待处理冲突（\(state.pendingConflictCount)）", systemImage: "exclamationmark.triangle")
                    }
                    .disabled(state.pendingConflictCount == 0)
                    Button("更改密码", systemImage: "key") { state.presentChangeMasterPassword() }
                    Menu {
                        Picker("自动锁定", selection: autoLockDurationBinding) {
                            ForEach(AutoLockDuration.allCases) { duration in
                                Text(duration.title).tag(duration)
                            }
                        }
                    } label: {
                        Label("设置", systemImage: "gearshape")
                    }
                    Button("锁定", systemImage: "lock") { state.lock() }
                }
            }
        } detail: {
            if let item = state.selectedItem {
                LoginDetailView(
                    item: item,
                    isPasswordRevealed: state.isPasswordRevealed,
                    revealPassword: state.togglePasswordReveal,
                    copyPassword: { _ = state.copySelectedPassword() },
                    clipboardSecondsRemaining: state.clipboardSecondsRemaining,
                    clearCopiedPassword: state.clearCopiedPassword,
                    deleteItem: { showingDeleteConfirmation = true },
                    changeMasterPassword: state.presentChangeMasterPassword,
                    state: state
                )
            } else {
                ContentUnavailableView("选择一条登录信息", systemImage: "key")
            }
        }
        .onChange(of: selectedID) { _, id in state.selectItem(id: id) }
        .onChange(of: state.items.map(\.id)) { _, ids in
            if let selectedID, !ids.contains(selectedID) { self.selectedID = nil }
        }
        .sheet(isPresented: $showingNewItem) { NewLoginItemView(state: state) }
        .sheet(isPresented: $state.isChangeMasterPasswordPresented) { ChangeMasterPasswordView(state: state) }
        .sheet(isPresented: $state.isExistingVaultImportPresented) { ExistingVaultImportView(state: state) }
        .sheet(isPresented: $state.isExportArchivePresented) { ExportArchiveView(state: state) }
        .sheet(isPresented: $state.isConflictCenterPresented) { ConflictCenterView(state: state) }
        .confirmationDialog("删除这条登录信息？", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("删除", role: .destructive) { state.deleteSelectedItem() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作无法撤销。")
        }
    }

    private var selectedCategoryBinding: Binding<String?> {
        Binding(get: { state.selectedCategory }, set: { state.selectCategory($0) })
    }

    private var autoLockDurationBinding: Binding<AutoLockDuration> {
        Binding(get: { state.autoLockDuration }, set: { state.setAutoLockDuration($0) })
    }
}

private struct ExistingVaultImportView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var state: VaultAppState
    @State private var archiveURL: URL?
    @State private var exportPassword = ""

    var body: some View {
        Form {
            Section("加密文件") {
                HStack {
                    Text(archiveURL?.lastPathComponent ?? "尚未选择文件")
                        .lineLimit(1)
                    Spacer()
                    Button("选择加密文件", action: chooseArchive)
                }
            }
            Section("导出密码") {
                SecureField("导出密码", text: $exportPassword)
                    .onChange(of: exportPassword) { _, _ in state.recordActivity() }
                Label("导入不会静默覆盖本地记录；不同内容将进入冲突中心。", systemImage: "lock.shield")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("导入加密文件", action: importArchive)
                    .buttonStyle(.borderedProminent)
                    .disabled(archiveURL == nil || exportPassword.isEmpty)
            }
        }
        .padding()
        .frame(width: 460)
    }

    @MainActor
    private func chooseArchive() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "pwdlock")!]
        panel.allowsOtherFileTypes = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            archiveURL = panel.url
        }
    }

    private func importArchive() {
        guard let archiveURL else { return }
        state.importIntoExistingVault(at: archiveURL, exportPassword: exportPassword)
        exportPassword = ""
        if !state.isExistingVaultImportPresented { dismiss() }
    }
}

private struct ConflictCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var state: VaultAppState
    @State private var selectedID: UUID?

    var body: some View {
        NavigationSplitView {
            List(state.pendingConflicts, selection: $selectedID) { conflict in
                VStack(alignment: .leading, spacing: 3) {
                    Text(conflict.title)
                    Text(conflict.createdAt.formatted(date: .numeric, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(conflict.id)
            }
            .navigationTitle("待处理冲突")
        } detail: {
            if let conflict = selectedConflict {
                ConflictDetailView(conflict: conflict, state: state)
            } else {
                ContentUnavailableView("选择一个冲突", systemImage: "exclamationmark.triangle")
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .onAppear {
            selectedID = selectedID ?? state.pendingConflicts.first?.id
        }
        .onChange(of: state.pendingConflicts.map(\.id)) { _, ids in
            if ids.isEmpty {
                dismiss()
            } else if selectedID == nil || !ids.contains(selectedID!) {
                selectedID = ids.first
            }
        }
    }

    private var selectedConflict: ImportConflict? {
        state.pendingConflicts.first { $0.id == selectedID }
    }
}

private struct ConflictDetailView: View {
    let conflict: ImportConflict
    @ObservedObject var state: VaultAppState
    @State private var isPasswordRevealed = false
    @State private var showingUseImportedConfirmation = false
    @State private var showingManualMerge = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                        GridRow {
                            Text("字段").foregroundStyle(.secondary)
                            Text("本地版本").fontWeight(.semibold)
                            Text("导入版本").fontWeight(.semibold)
                        }
                        comparisonRow("标题", conflict.local.item.title, conflict.imported.item.title)
                        comparisonRow("用户名", conflict.local.item.username, conflict.imported.item.username)
                        comparisonRow("密码", masked(conflict.local.item.password), masked(conflict.imported.item.password))
                        comparisonRow("网站", conflict.local.item.url, conflict.imported.item.url)
                        comparisonRow("分类", conflict.local.item.category, conflict.imported.item.category)
                        comparisonRow("备注", conflict.local.item.note, conflict.imported.item.note)
                        comparisonRow("创建时间", dateText(conflict.local.item.createdAt), dateText(conflict.imported.item.createdAt))
                        comparisonRow("更新时间", dateText(conflict.local.item.updatedAt), dateText(conflict.imported.item.updatedAt))
                        comparisonRow("修订号", String(conflict.local.item.revision), String(conflict.imported.item.revision))
                        comparisonRow("设备 ID", conflict.local.item.deviceID.uuidString, conflict.imported.item.deviceID.uuidString)
                    }
                    Button(isPasswordRevealed ? "隐藏密码" : "显示密码") {
                        isPasswordRevealed.toggle()
                    }
                }
            }

            Divider()
            HStack {
                Button("保留本地版本") { state.keepLocal(conflictID: conflict.id) }
                Spacer()
                Button("手动合并") { showingManualMerge = true }
                Button("使用导入版本") { showingUseImportedConfirmation = true }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .navigationTitle(conflict.title)
        .confirmationDialog(
            "使用导入版本替换当前本地记录？",
            isPresented: $showingUseImportedConfirmation,
            titleVisibility: .visible
        ) {
            Button("使用导入版本", role: .destructive) {
                state.useImported(conflictID: conflict.id)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("本地版本将被导入版本替换，此操作无法撤销。")
        }
        .sheet(isPresented: $showingManualMerge) {
            ManualMergeView(conflict: conflict, state: state)
        }
    }

    @ViewBuilder
    private func comparisonRow(_ label: String, _ local: String, _ imported: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(local.isEmpty ? "—" : local).textSelection(.enabled)
            Text(imported.isEmpty ? "—" : imported).textSelection(.enabled)
        }
    }

    private func masked(_ password: String) -> String {
        isPasswordRevealed ? password : String(repeating: "•", count: max(password.count, 8))
    }

    private func dateText(_ date: Date) -> String {
        date.formatted(date: .numeric, time: .standard)
    }
}

private struct ManualMergeView: View {
    @Environment(\.dismiss) private var dismiss
    let conflict: ImportConflict
    @ObservedObject var state: VaultAppState
    @State private var title: String
    @State private var username: String
    @State private var password: String
    @State private var url: String
    @State private var category: String
    @State private var note: String
    @State private var expectedLocal: LoginItem

    init(conflict: ImportConflict, state: VaultAppState) {
        self.conflict = conflict
        self.state = state
        let local = conflict.local.item
        _title = State(initialValue: local.title)
        _username = State(initialValue: local.username)
        _password = State(initialValue: local.password)
        _url = State(initialValue: local.url)
        _category = State(initialValue: local.category)
        _note = State(initialValue: local.note)
        _expectedLocal = State(initialValue: local)
    }

    var body: some View {
        Form {
            Section("手动合并") {
                mergeField("标题", text: $title, imported: conflict.imported.item.title)
                mergeField("用户名", text: $username, imported: conflict.imported.item.username)
                HStack {
                    SecureField("密码", text: $password)
                    Button("采用导入密码") { password = conflict.imported.item.password }
                }
                mergeField("网站", text: $url, imported: conflict.imported.item.url)
                mergeField("分类", text: $category, imported: conflict.imported.item.category)
                mergeField("备注", text: $note, imported: conflict.imported.item.note)
            }
            Text("保存后将生成同一记录的新修订版本。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存合并结果") {
                    if state.mergeManually(
                        conflictID: conflict.id,
                        merge: ManualLoginMerge(
                            title: title,
                            username: username,
                            password: password,
                            url: url,
                            category: category,
                            note: note
                        ),
                        expectedLocal: expectedLocal
                    ) {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.isEmpty)
            }
        }
        .padding()
        .frame(width: 460)
    }

    @ViewBuilder
    private func mergeField(_ label: String, text: Binding<String>, imported: String) -> some View {
        HStack {
            TextField(label, text: text)
            Button("采用导入") { text.wrappedValue = imported }
        }
    }
}

private struct ImportArchiveView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var state: VaultAppState
    @State private var archiveURL: URL?
    @State private var exportPassword = ""
    @State private var exportPasswordConfirmation = ""
    @State private var newMasterPassword = ""
    @State private var newMasterPasswordConfirmation = ""

    var body: some View {
        Form {
            Section("加密文件") {
                HStack {
                    Text(archiveURL?.lastPathComponent ?? "尚未选择文件")
                        .lineLimit(1)
                    Spacer()
                    Button("选择加密文件", action: chooseArchive)
                }
            }
            Section("导出密码") {
                SecureField("导出密码", text: $exportPassword).onChange(of: exportPassword) { _, _ in state.recordActivity() }
                SecureField("确认导出密码", text: $exportPasswordConfirmation).onChange(of: exportPasswordConfirmation) { _, _ in state.recordActivity() }
            }
            Section("新的本地主密码") {
                SecureField("新的本地主密码", text: $newMasterPassword).onChange(of: newMasterPassword) { _, _ in state.recordActivity() }
                SecureField("确认新的本地主密码", text: $newMasterPasswordConfirmation).onChange(of: newMasterPasswordConfirmation) { _, _ in state.recordActivity() }
                Text("至少使用 12 个字符。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("忘记主密码将无法恢复。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("导入", action: importArchive)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canImport)
            }
        }
        .padding()
        .frame(width: 460)
    }

    private var canImport: Bool {
        archiveURL != nil
            && !exportPassword.isEmpty
            && exportPassword == exportPasswordConfirmation
            && newMasterPassword == newMasterPasswordConfirmation
            && MasterPasswordPolicy.isValid(newMasterPassword)
    }

    @MainActor
    private func chooseArchive() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "pwdlock")!]
        panel.allowsOtherFileTypes = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            archiveURL = panel.url
        }
    }

    private func importArchive() {
        guard let archiveURL else { return }
        state.importArchive(
            at: archiveURL,
            exportPassword: exportPassword,
            exportPasswordConfirmation: exportPasswordConfirmation,
            newMasterPassword: newMasterPassword,
            newMasterPasswordConfirmation: newMasterPasswordConfirmation
        )
        exportPassword = ""
        exportPasswordConfirmation = ""
        newMasterPassword = ""
        newMasterPasswordConfirmation = ""
        if state.screen == .library { dismiss() }
    }
}

private struct ExportArchiveView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var state: VaultAppState
    @State private var exportPassword = ""
    @State private var confirmation = ""

    var body: some View {
        Form {
            SecureField("导出密码", text: $exportPassword).onChange(of: exportPassword) { _, _ in state.recordActivity() }
            SecureField("确认导出密码", text: $confirmation).onChange(of: confirmation) { _, _ in state.recordActivity() }
            Text("导出密码用于加密此文件，请不要重复使用主密码。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("导出密码库", action: chooseExportDestination)
                    .buttonStyle(.borderedProminent)
                    .disabled(exportPassword.isEmpty || exportPassword != confirmation)
            }
        }
        .padding()
        .frame(width: 420)
    }

    @MainActor
    private func chooseExportDestination() {
        guard !exportPassword.isEmpty, exportPassword == confirmation else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "pwdlock")!]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "密码库.pwdlock"
        if panel.runModal() == .OK, let archiveURL = panel.url {
            state.exportArchive(to: archiveURL, exportPassword: exportPassword, confirmation: confirmation)
            exportPassword = ""
            confirmation = ""
            if !state.isExportArchivePresented { dismiss() }
        }
    }
}

private struct LoginDetailView: View {
    let item: LoginItem
    let isPasswordRevealed: Bool
    let revealPassword: () -> Void
    let copyPassword: () -> Void
    let clipboardSecondsRemaining: Int?
    let clearCopiedPassword: () -> Void
    let deleteItem: () -> Void
    let changeMasterPassword: () -> Void
    @ObservedObject var state: VaultAppState
    @State private var showingEdit = false

    var body: some View {
        Form {
            Section {
                LabeledContent("用户名", value: item.username)
                LabeledContent("密码") {
                    HStack {
                        Text(isPasswordRevealed ? item.password : String(repeating: "•", count: max(item.password.count, 8)))
                        Button(isPasswordRevealed ? "隐藏" : "显示", action: revealPassword)
                        Button("复制", action: copyPassword)
                    }
                }
                if let clipboardSecondsRemaining {
                    ClipboardStatusView(
                        clipboardSecondsRemaining: clipboardSecondsRemaining,
                        clearCopiedPassword: clearCopiedPassword
                    )
                }
                LabeledContent("网站", value: item.url)
                LabeledContent("分类", value: item.category)
                if !item.note.isEmpty { LabeledContent("备注", value: item.note) }
            }
        }
        .navigationTitle(item.title)
        .toolbar {
            ToolbarItemGroup {
                Button("编辑") { showingEdit = true }
                Button("删除", role: .destructive, action: deleteItem)
                Menu("密码库") {
                    Button("更改主密码", action: changeMasterPassword)
                }
            }
        }
        .sheet(isPresented: $showingEdit) { EditLoginItemView(item: item, state: state) }
    }
}

private struct ClipboardStatusView: View {
    let clipboardSecondsRemaining: Int
    let clearCopiedPassword: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("密码已复制，将在 \(clipboardSecondsRemaining) 秒后清除")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("清除剪贴板", action: clearCopiedPassword)
            }
        }
    }
}

private struct NewLoginItemView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var state: VaultAppState
    @State private var title = ""
    @State private var username = ""
    @State private var password = ""
    @State private var url = ""
    @State private var category = ""
    @State private var note = ""

    var body: some View {
        Form {
            TextField("标题", text: $title).onChange(of: title) { _, _ in state.recordActivity() }
            TextField("用户名", text: $username).onChange(of: username) { _, _ in state.recordActivity() }
            SecureField("密码", text: $password).onChange(of: password) { _, _ in state.recordActivity() }
            TextField("网站", text: $url).onChange(of: url) { _, _ in state.recordActivity() }
            TextField("分类", text: $category).onChange(of: category) { _, _ in state.recordActivity() }
            TextField("备注", text: $note).onChange(of: note) { _, _ in state.recordActivity() }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("添加") {
                    state.addItem(title: title, username: username, password: password, url: url, category: category, note: note)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.isEmpty)
            }
        }
        .padding()
        .frame(width: 420)
    }
}

private struct EditLoginItemView: View {
    @Environment(\.dismiss) private var dismiss
    let item: LoginItem
    @ObservedObject var state: VaultAppState
    @State private var title: String
    @State private var username: String
    @State private var password: String
    @State private var url: String
    @State private var category: String
    @State private var note: String

    init(item: LoginItem, state: VaultAppState) {
        self.item = item
        self.state = state
        _title = State(initialValue: item.title)
        _username = State(initialValue: item.username)
        _password = State(initialValue: item.password)
        _url = State(initialValue: item.url)
        _category = State(initialValue: item.category)
        _note = State(initialValue: item.note)
    }

    var body: some View {
        Form {
            TextField("标题", text: $title).onChange(of: title) { _, _ in state.recordActivity() }
            TextField("用户名", text: $username).onChange(of: username) { _, _ in state.recordActivity() }
            SecureField("密码", text: $password).onChange(of: password) { _, _ in state.recordActivity() }
            TextField("网站", text: $url).onChange(of: url) { _, _ in state.recordActivity() }
            TextField("分类", text: $category).onChange(of: category) { _, _ in state.recordActivity() }
            TextField("备注", text: $note).onChange(of: note) { _, _ in state.recordActivity() }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") {
                    state.editSelectedItem(
                        title: title,
                        username: username,
                        password: password,
                        url: url,
                        category: category,
                        note: note
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.isEmpty)
            }
        }
        .padding()
        .frame(width: 420)
    }
}

private struct ChangeMasterPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var state: VaultAppState
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmation = ""

    var body: some View {
        Form {
            SecureField("当前密码", text: $currentPassword).onChange(of: currentPassword) { _, _ in state.recordActivity() }
            SecureField("新密码", text: $newPassword).onChange(of: newPassword) { _, _ in state.recordActivity() }
            SecureField("确认新密码", text: $confirmation).onChange(of: confirmation) { _, _ in state.recordActivity() }
            Text("至少使用 12 个字符。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("忘记主密码将无法恢复。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("更改密码") {
                    state.changeMasterPassword(currentPassword: currentPassword, newPassword: newPassword, confirmation: confirmation)
                    currentPassword = ""
                    newPassword = ""
                    confirmation = ""
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    currentPassword.isEmpty
                        || newPassword != confirmation
                        || !MasterPasswordPolicy.isValid(newPassword)
                )
            }
        }
        .padding()
        .frame(width: 420)
    }
}
