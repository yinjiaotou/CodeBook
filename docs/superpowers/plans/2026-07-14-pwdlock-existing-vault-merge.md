# Pwdlock 已有密码库导入合并与冲突中心 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在已解锁的 macOS 密码库中安全导入 `.pwdlock` v1，将新增、相同和冲突记录事务化处理，并提供中文冲突裁决界面。

**Architecture:** `PwdlockArchive` 继续只负责认证解密与协议校验；新增领域模型表达合并摘要与冲突，`LoginItemRepository` 在单个 SQLCipher 事务内完成合并和裁决，`VaultSession` 负责安全读取文件并协调仓储，`VaultAppState` 与 SwiftUI 只管理交互状态。冲突的两个完整变体以规范 JSON 存在同一加密数据库中，当前本地记录在裁决前不变。

**Tech Stack:** Swift 6.2、Swift Testing、SwiftUI、SQLCipher/SQLite C API、现有 `.pwdlock` v1 Argon2id + AES-GCM 实现。

---

## 文件结构

- Create: `platforms/macos/PwdlockMac/Sources/PwdlockCore/Domain/ImportConflict.swift` — 合并摘要、冲突组、冲突变体与手动合并输入。
- Modify: `platforms/macos/PwdlockMac/Sources/PwdlockCore/Persistence/LoginItemRepository.swift` — 表迁移、事务合并、冲突读取与三类裁决。
- Modify: `platforms/macos/PwdlockMac/Sources/PwdlockCore/Application/VaultSession.swift` — 已解锁文件导入协调与安全文件读取复用。
- Modify: `platforms/macos/PwdlockMac/Sources/PwdlockMacApp/VaultAppState.swift` — 导入表单状态、摘要、冲突刷新与裁决动作。
- Modify: `platforms/macos/PwdlockMac/Sources/PwdlockMacApp/VaultViews.swift` — 工具栏入口、导入表单、摘要和冲突中心。
- Create: `platforms/macos/PwdlockMac/Tests/PwdlockCoreTests/ImportConflictRepositoryTests.swift` — 合并、去重、回滚和裁决测试。
- Modify: `platforms/macos/PwdlockMac/Tests/PwdlockCoreTests/VaultSessionTests.swift` — 已解锁导入的文件与会话边界测试。
- Modify: `platforms/macos/PwdlockMac/Tests/PwdlockMacAppTests/VaultAppStateTests.swift` — 中文状态与交互测试。
- Modify: `platforms/macos/PwdlockMac/Tests/PwdlockMacAppTests/VaultViewsLayoutTests.swift` — 入口、密码遮蔽和操作文案的静态回归测试。

### Task 1: 定义导入合并领域模型

**Files:**
- Create: `platforms/macos/PwdlockMac/Sources/PwdlockCore/Domain/ImportConflict.swift`
- Test: `platforms/macos/PwdlockMac/Tests/PwdlockCoreTests/ImportConflictRepositoryTests.swift`

- [ ] **Step 1: 写失败测试，固定摘要和手动合并输入的类型契约**

```swift
import Foundation
import Testing
@testable import PwdlockCore

@Test("import merge summary exposes added identical and conflict counts")
func importMergeSummaryContract() {
    let summary = ImportMergeSummary(added: 2, identical: 3, conflicts: 1)
    #expect(summary == ImportMergeSummary(added: 2, identical: 3, conflicts: 1))
}

@Test("manual merge input contains only editable business fields")
func manualMergeInputContract() {
    let input = ManualLoginMerge(title: "GitHub", username: "yin", password: "secret", url: "https://github.com", category: "工作", note: "主账号")
    #expect(input.title == "GitHub")
    #expect(input.note == "主账号")
}
```

- [ ] **Step 2: 运行测试确认 RED**

Run: `cd platforms/macos/PwdlockMac && swift test --filter ImportConflictRepositoryTests`

Expected: FAIL，提示 `ImportMergeSummary` 和 `ManualLoginMerge` 未定义。

- [ ] **Step 3: 添加最小领域模型**

```swift
import Foundation

public struct ImportMergeSummary: Equatable, Sendable {
    public let added: Int
    public let identical: Int
    public let conflicts: Int
    public init(added: Int, identical: Int, conflicts: Int) {
        self.added = added; self.identical = identical; self.conflicts = conflicts
    }
}

public enum ConflictVariantKind: String, Codable, Sendable { case local, imported }

public struct ConflictVariant: Equatable, Sendable {
    public let id: UUID
    public let kind: ConflictVariantKind
    public let sourceVaultID: UUID
    public let item: LoginItem
}

public struct ImportConflict: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let recordID: UUID
    public let title: String
    public let createdAt: Date
    public let local: ConflictVariant
    public let imported: ConflictVariant
}

public struct ManualLoginMerge: Equatable, Sendable {
    public var title: String
    public var username: String
    public var password: String
    public var url: String
    public var category: String
    public var note: String
    public init(title: String, username: String, password: String, url: String, category: String, note: String) {
        self.title = title; self.username = username; self.password = password
        self.url = url; self.category = category; self.note = note
    }
}
```

- [ ] **Step 4: 运行测试确认 GREEN**

Run: `cd platforms/macos/PwdlockMac && swift test --filter ImportConflictRepositoryTests`

Expected: PASS。

- [ ] **Step 5: 提交该原子变更**

```bash
git add platforms/macos/PwdlockMac/Sources/PwdlockCore/Domain/ImportConflict.swift platforms/macos/PwdlockMac/Tests/PwdlockCoreTests/ImportConflictRepositoryTests.swift
git commit -m "feat(mac): define import conflict models"
```

### Task 2: 迁移冲突表并实现事务合并

**Files:**
- Modify: `platforms/macos/PwdlockMac/Sources/PwdlockCore/Persistence/LoginItemRepository.swift`
- Test: `platforms/macos/PwdlockMac/Tests/PwdlockCoreTests/ImportConflictRepositoryTests.swift`

- [ ] **Step 1: 写失败测试覆盖新增、相同、冲突和重复导入**

```swift
@Test("merge adds missing skips identical and preserves differing local item")
func mergesArchiveRecordsAtomically() throws {
    let fixture = try RepositoryFixture()
    defer { fixture.close() }
    let local = fixture.item(id: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!, title: "本地")
    let identical = fixture.item(id: UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!, title: "相同")
    try fixture.repository.create(local)
    try fixture.repository.create(identical)
    let importedConflict = fixture.copy(local, title: "导入")
    let added = fixture.item(id: UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")!, title: "新增")

    let summary = try fixture.repository.mergeImportedItems(
        [identical, importedConflict, added],
        sourceVaultID: UUID(uuidString: "dddddddd-dddd-4ddd-8ddd-dddddddddddd")!,
        now: Date(timeIntervalSince1970: 1_800_000_000)
    )

    #expect(summary == ImportMergeSummary(added: 1, identical: 1, conflicts: 1))
    #expect(try fixture.repository.item(id: local.id) == local)
    #expect(try fixture.repository.pendingConflicts().count == 1)
    #expect(try fixture.repository.mergeImportedItems([importedConflict], sourceVaultID: UUID(uuidString: "dddddddd-dddd-4ddd-8ddd-dddddddddddd")!, now: Date()).conflicts == 0)
}
```

- [ ] **Step 2: 运行测试确认 RED**

Run: `cd platforms/macos/PwdlockMac && swift test --filter mergesArchiveRecordsAtomically`

Expected: FAIL，提示 `mergeImportedItems`/`pendingConflicts` 不存在。

- [ ] **Step 3: 扩展迁移和公开 API**

在 `migrate()` 追加以下 SQL，并为 `conflict_variants.group_id` 开启级联删除：

```sql
PRAGMA foreign_keys = ON;
CREATE TABLE IF NOT EXISTS conflict_groups (
    id TEXT PRIMARY KEY NOT NULL,
    record_id TEXT NOT NULL,
    title TEXT NOT NULL,
    created_at_ms INTEGER NOT NULL,
    state TEXT NOT NULL CHECK(state = 'pending')
);
CREATE TABLE IF NOT EXISTS conflict_variants (
    id TEXT PRIMARY KEY NOT NULL,
    group_id TEXT NOT NULL REFERENCES conflict_groups(id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK(kind IN ('local', 'imported')),
    source_vault_id TEXT NOT NULL,
    payload BLOB NOT NULL,
    UNIQUE(group_id, kind)
);
CREATE INDEX IF NOT EXISTS idx_conflict_groups_record ON conflict_groups(record_id, state);
```

新增仓储入口：

```swift
public func mergeImportedItems(_ items: [LoginItem], importedSourceVaultID: UUID, localSourceVaultID: UUID, now: Date = Date()) throws -> ImportMergeSummary
public func pendingConflicts() throws -> [ImportConflict]
public func pendingConflictCount() throws -> Int
```

实现必须使用 `BEGIN IMMEDIATE`/`COMMIT`，任何错误由 `defer` 执行 `ROLLBACK`。逐条读取现有 `payload`：不存在则调用当前 `insert`；`LoginItem == imported` 则计为相同；不同时将本地和导入 JSON 编码后，查询同 `record_id`、同导入来源 `source_vault_id` 且两份 payload 字节都相同的现有组，只有查不到时才插入一个 group 和两个 variant。本地变体写 `localSourceVaultID`，导入变体写 `importedSourceVaultID`。返回值只统计本次实际新增的冲突。

- [ ] **Step 4: 添加故障注入并验证事务回滚**

为测试增加内部参数：

```swift
func mergeImportedItems(
    _ items: [LoginItem],
    sourceVaultID: UUID,
    now: Date = Date(),
    beforeCommit: () throws -> Void = {}
) throws -> ImportMergeSummary
```

测试传入 `{ throw SyntheticFailure() }`，断言新增记录不存在且冲突数为零。

- [ ] **Step 5: 运行仓储测试确认 GREEN**

Run: `cd platforms/macos/PwdlockMac && swift test --filter ImportConflictRepositoryTests`

Expected: PASS，包含新增/相同/冲突/去重/回滚用例。

- [ ] **Step 6: 提交该原子变更**

```bash
git add platforms/macos/PwdlockMac/Sources/PwdlockCore/Persistence/LoginItemRepository.swift platforms/macos/PwdlockMac/Tests/PwdlockCoreTests/ImportConflictRepositoryTests.swift
git commit -m "feat(mac): merge imported records transactionally"
```

### Task 3: 实现三类冲突裁决

**Files:**
- Modify: `platforms/macos/PwdlockMac/Sources/PwdlockCore/Persistence/LoginItemRepository.swift`
- Test: `platforms/macos/PwdlockMac/Tests/PwdlockCoreTests/ImportConflictRepositoryTests.swift`

- [ ] **Step 1: 写失败测试覆盖保留本地、使用导入和手动合并**

```swift
@Test("all conflict resolutions are transactional")
func resolvesConflictVariants() throws {
    let fixture = try RepositoryFixture()
    defer { fixture.close() }
    let local = fixture.item(title: "本地")
    let imported = fixture.copy(local, title: "导入", revision: 8)
    try fixture.repository.create(local)
    _ = try fixture.repository.mergeImportedItems([imported], sourceVaultID: fixture.sourceVaultID)
    let conflict = try #require(fixture.repository.pendingConflicts().first)

    try fixture.repository.resolveUsingImported(conflictID: conflict.id)
    #expect(try fixture.repository.item(id: local.id) == imported)
    #expect(try fixture.repository.pendingConflictCount() == 0)
}
```

另建两个独立 fixture：`resolveKeepingLocal` 后本地不变；`resolveManually` 后断言业务字段来自输入、`id/createdAt/deviceID` 来自本地、`revision == max(local, imported) + 1`、`updatedAt == now`。

- [ ] **Step 2: 运行测试确认 RED**

Run: `cd platforms/macos/PwdlockMac && swift test --filter resolvesConflictVariants`

Expected: FAIL，三个裁决 API 未定义。

- [ ] **Step 3: 实现事务裁决 API**

```swift
public func resolveKeepingLocal(conflictID: UUID) throws
public func resolveUsingImported(conflictID: UUID) throws
public func resolveManually(conflictID: UUID, merge: ManualLoginMerge, now: Date = Date()) throws
```

三个方法都先在事务内加载恰好一个 `pending` 冲突和两个变体，否则抛 `itemNotFound`。保留本地只删除 group；使用导入调用内部 `update(_:on:)` 后删 group；手动合并构造以下记录后更新并删 group：

```swift
let merged = LoginItem(
    id: local.id,
    title: merge.title,
    username: merge.username,
    password: merge.password,
    url: merge.url,
    category: merge.category,
    note: merge.note,
    createdAt: local.createdAt,
    updatedAt: now,
    revision: max(local.revision, imported.revision) + 1,
    deviceID: local.deviceID
)
```

- [ ] **Step 4: 运行测试确认 GREEN**

Run: `cd platforms/macos/PwdlockMac && swift test --filter ImportConflictRepositoryTests`

Expected: PASS。

- [ ] **Step 5: 提交该原子变更**

```bash
git add platforms/macos/PwdlockMac/Sources/PwdlockCore/Persistence/LoginItemRepository.swift platforms/macos/PwdlockMac/Tests/PwdlockCoreTests/ImportConflictRepositoryTests.swift
git commit -m "feat(mac): resolve imported record conflicts"
```

### Task 4: 在已解锁 VaultSession 中安全导入

**Files:**
- Modify: `platforms/macos/PwdlockMac/Sources/PwdlockCore/Application/VaultSession.swift`
- Modify: `platforms/macos/PwdlockMac/Tests/PwdlockCoreTests/VaultSessionTests.swift`

- [ ] **Step 1: 写失败测试**

```swift
@Test("unlocked session imports archive into existing vault")
func importsArchiveIntoUnlockedVault() throws {
    let fixture = try VaultSessionFixture.unlocked()
    defer { fixture.remove() }
    let archiveURL = try fixture.writeArchive(records: [fixture.portableRecord(title: "导入")], password: "export-passphrase")
    let summary = try fixture.session.mergeArchive(at: archiveURL, exportPassword: "export-passphrase")
    #expect(summary.added == 1)
    #expect(try fixture.session.loginItemRepository().search(query: "导入").count == 1)
}
```

再覆盖 locked 会话、错误密码、超限文件、读取后 `fstat` 尺寸变化均不修改库。

- [ ] **Step 2: 运行测试确认 RED**

Run: `cd platforms/macos/PwdlockMac && swift test --filter importsArchiveIntoUnlockedVault`

Expected: FAIL，`mergeArchive` 未定义。

- [ ] **Step 3: 提取并复用安全读取 helper，添加会话 API**

```swift
public func mergeArchive(at archiveURL: URL, exportPassword: String) throws -> ImportMergeSummary {
    guard database != nil else { throw VaultSessionError.locked }
    let data = try readAndVerifyArchive(at: archiveURL)
    let payload = try PwdlockArchive.import(data: data, password: exportPassword)
    let items = try payload.records.map(loginItem)
    let metadata = try metadataStore.load()
    return try loginItemRepository().mergeImportedItems(
        items,
        importedSourceVaultID: payload.sourceVaultId,
        localSourceVaultID: try uuid(from: metadata.vaultID)
    )
}
```

`readAndVerifyArchive` 必须沿用首次导入的同一文件描述符 `fstat → 限量读取 → fstat` 逻辑；首次导入也改为调用该 helper，避免出现两套安全策略。`PwdlockArchive` 继续拒绝非空墓碑和外部冲突组。

- [ ] **Step 4: 运行会话测试确认 GREEN**

Run: `cd platforms/macos/PwdlockMac && swift test --filter VaultSessionTests`

Expected: PASS。

- [ ] **Step 5: 提交该原子变更**

```bash
git add platforms/macos/PwdlockMac/Sources/PwdlockCore/Application/VaultSession.swift platforms/macos/PwdlockMac/Tests/PwdlockCoreTests/VaultSessionTests.swift
git commit -m "feat(mac): import archives into unlocked vault"
```

### Task 5: 连接 AppState 导入与冲突状态

**Files:**
- Modify: `platforms/macos/PwdlockMac/Sources/PwdlockMacApp/VaultAppState.swift`
- Modify: `platforms/macos/PwdlockMac/Tests/PwdlockMacAppTests/VaultAppStateTests.swift`

- [ ] **Step 1: 写失败测试固定中文摘要和裁决刷新行为**

```swift
@Test("existing vault import publishes summary and pending conflict count")
@MainActor func existingVaultImportState() throws {
    let fixture = try AppStateFixture.unlocked()
    let archive = try fixture.writeArchiveWithOneAddedAndOneConflict()
    fixture.state.importIntoExistingVault(at: archive, exportPassword: "export-passphrase")
    #expect(fixture.state.operationSummary == "导入完成：新增 1 项，已存在 0 项，待处理冲突 1 项。")
    #expect(fixture.state.pendingConflictCount == 1)
    #expect(fixture.state.isExistingVaultImportPresented == false)
}
```

- [ ] **Step 2: 运行测试确认 RED**

Run: `cd platforms/macos/PwdlockMac && swift test --filter existingVaultImportState`

Expected: FAIL，相关状态和方法未定义。

- [ ] **Step 3: 添加状态与动作**

```swift
@Published var isExistingVaultImportPresented = false
@Published var isConflictCenterPresented = false
@Published private(set) var pendingConflicts: [ImportConflict] = []
var pendingConflictCount: Int { pendingConflicts.count }

func presentExistingVaultImport()
func importIntoExistingVault(at url: URL, exportPassword: String)
func refreshConflicts()
func keepLocal(conflictID: UUID)
func useImported(conflictID: UUID)
func mergeManually(conflictID: UUID, merge: ManualLoginMerge)
```

成功导入后关闭表单、刷新列表和冲突；失败统一显示“密码错误或文件损坏，未修改当前密码库。”；裁决失败显示“无法处理此冲突。”。`resetLockedState()` 必须清空冲突和关闭两个表单。

- [ ] **Step 4: 运行状态测试确认 GREEN**

Run: `cd platforms/macos/PwdlockMac && swift test --filter VaultAppStateTests`

Expected: PASS。

- [ ] **Step 5: 提交该原子变更**

```bash
git add platforms/macos/PwdlockMac/Sources/PwdlockMacApp/VaultAppState.swift platforms/macos/PwdlockMac/Tests/PwdlockMacAppTests/VaultAppStateTests.swift
git commit -m "feat(mac): expose import conflict app state"
```

### Task 6: 构建导入表单与冲突中心

**Files:**
- Modify: `platforms/macos/PwdlockMac/Sources/PwdlockMacApp/VaultViews.swift`
- Modify: `platforms/macos/PwdlockMac/Tests/PwdlockMacAppTests/VaultViewsLayoutTests.swift`

- [ ] **Step 1: 写失败的静态 UI 回归测试**

```swift
@Test("library exposes import and conflict center while conflict password stays masked")
func importConflictUIContract() throws {
    let source = try String(contentsOf: vaultViewsURL, encoding: .utf8)
    #expect(source.contains("导入加密文件"))
    #expect(source.contains("不会静默覆盖本地记录"))
    #expect(source.contains("待处理冲突"))
    #expect(source.contains("使用导入版本"))
    #expect(source.contains("保留本地版本"))
    #expect(source.contains("String(repeating: \"•\""))
}
```

- [ ] **Step 2: 运行测试确认 RED**

Run: `cd platforms/macos/PwdlockMac && swift test --filter importConflictUIContract`

Expected: FAIL，入口和冲突文案不存在。

- [ ] **Step 3: 添加 SwiftUI 入口与表单**

工具栏加入 `Button("导入加密文件", systemImage: "square.and.arrow.down")`，设置 `isExistingVaultImportPresented`；冲突徽标按钮显示 `待处理冲突（N）`。新增 `ExistingVaultImportView`：选择 `.pwdlock`、输入一次独立导出密码、明确显示“导入不会静默覆盖本地记录”，确认后调用 `importIntoExistingVault`。

- [ ] **Step 4: 添加冲突中心和手动合并表单**

新增 `ConflictCenterView` 与 `ManualMergeView`。详情对比标题、用户名、密码、网站、分类、备注、创建时间、更新时间、修订号和设备 ID；两侧密码默认用至少 8 个圆点遮蔽，并提供一次性的“显示密码”。底部提供“保留本地版本”“使用导入版本”“手动合并”，后两项使用确认对话框；手动表单只编辑六个业务字段。

- [ ] **Step 5: 运行 UI 与完整测试确认 GREEN**

Run: `cd platforms/macos/PwdlockMac && swift test`

Expected: 全部测试 PASS，且现有复制布局测试继续通过。

- [ ] **Step 6: 提交该原子变更**

```bash
git add platforms/macos/PwdlockMac/Sources/PwdlockMacApp/VaultViews.swift platforms/macos/PwdlockMac/Tests/PwdlockMacAppTests/VaultViewsLayoutTests.swift
git commit -m "feat(mac): add import conflict center UI"
```

### Task 7: 构建与手工验收

**Files:**
- Modify only if verification exposes a scoped defect.

- [ ] **Step 1: 运行完整测试**

Run: `cd platforms/macos/PwdlockMac && swift test`

Expected: 所有测试 PASS，无失败或意外跳过。

- [ ] **Step 2: 运行 release 构建**

Run: `cd platforms/macos/PwdlockMac && swift build -c release`

Expected: `Build complete!`。

- [ ] **Step 3: 手工验证真实 `.pwdlock` 文件**

使用临时密码库准备一条新增、一条相同、一条同 ID 不同内容记录；导入后确认摘要为 1/1/1，本地冲突记录仍生效，重复导入不增加冲突，然后逐一验证三种裁决和密码默认遮蔽。

- [ ] **Step 4: 进入 Touch ID 计划前记录基线**

Run: `cd platforms/macos/PwdlockMac && swift test 2>&1 | tail -20`

Expected: 末尾显示测试运行成功；将实际测试总数记录在执行日志中。
