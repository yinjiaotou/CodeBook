# Pwdlock macOS Touch ID 快捷解锁 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 macOS 密码库加入仅限本机、绑定当前指纹集合的 Touch ID 快捷解锁，并在解锁页每轮自动提示一次，同时永久保留主密码入口。

**Architecture:** PwdlockCore 将生物认证能力、Keychain 密钥存储和 Vault Key 包装文件拆成三个可替换单元；`VaultSession` 只协调这些单元并记录当前解锁来源；`VaultAppState` 管理自动提示一次和手动重试；SwiftUI 提供设置开关与解锁按钮。Keychain 只保存随机 Biometric Wrap Key，`vault.biometric` 只保存经 AES-GCM 包装的 Vault Key，两者都不进入备份或导出。

**Tech Stack:** Swift 6.2、CryptoKit AES-GCM、LocalAuthentication、Security.framework Keychain、Swift Testing、SwiftUI、SQLCipher。

---

## 文件结构

- Create: `platforms/macos/PwdlockMac/Sources/PwdlockCore/Security/BiometricVaultEnvelope.swift` — 固定格式包装文件编码、认证解包和原子保存。
- Create: `platforms/macos/PwdlockMac/Sources/PwdlockCore/Security/BiometricKeyStore.swift` — Keychain 协议、Security.framework 实现及错误分类。
- Create: `platforms/macos/PwdlockMac/Sources/PwdlockCore/Application/BiometricAuthenticator.swift` — LocalAuthentication 协议、系统实现和取消能力。
- Modify: `platforms/macos/PwdlockMac/Sources/PwdlockCore/Application/VaultSession.swift` — 启用、关闭、快捷解锁、清理和解锁来源。
- Modify: `platforms/macos/PwdlockMac/Sources/PwdlockMacApp/VaultAppState.swift` — 自动提示一次、手动重试、设置状态和后台取消。
- Modify: `platforms/macos/PwdlockMac/Sources/PwdlockMacApp/VaultViews.swift` — 解锁按钮和设置开关。
- Create: `platforms/macos/PwdlockMac/Tests/PwdlockCoreTests/BiometricVaultEnvelopeTests.swift`
- Create: `platforms/macos/PwdlockMac/Tests/PwdlockCoreTests/BiometricKeyStoreTests.swift`
- Modify: `platforms/macos/PwdlockMac/Tests/PwdlockCoreTests/VaultSessionTests.swift`
- Modify: `platforms/macos/PwdlockMac/Tests/PwdlockMacAppTests/VaultAppStateTests.swift`
- Modify: `platforms/macos/PwdlockMac/Tests/PwdlockMacAppTests/VaultViewsLayoutTests.swift`

### Task 1: 实现认证的 Vault Key 包装格式

**Files:**
- Create: `platforms/macos/PwdlockMac/Sources/PwdlockCore/Security/BiometricVaultEnvelope.swift`
- Create: `platforms/macos/PwdlockMac/Tests/PwdlockCoreTests/BiometricVaultEnvelopeTests.swift`

- [ ] **Step 1: 写失败测试覆盖 round-trip 和逐字段篡改**

```swift
import Foundation
import Testing
@testable import PwdlockCore

@Test("biometric envelope round trips vault key")
func biometricEnvelopeRoundTrip() throws {
    let bytes = try BiometricVaultEnvelope.seal(
        vaultKey: Data(0..<32),
        wrappingKey: Data(32..<64),
        vaultID: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!,
        nonce: Data(repeating: 0x44, count: 12)
    )
    #expect(try BiometricVaultEnvelope.open(bytes, wrappingKey: Data(32..<64), expectedVaultID: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!) == Data(0..<32))
}
```

复制 bytes 并分别修改魔数、版本、Vault ID、nonce、密文和 tag，全部断言抛 `BiometricVaultEnvelopeError.invalidEnvelope` 或 `authenticationFailed`。

- [ ] **Step 2: 运行测试确认 RED**

Run: `cd platforms/macos/PwdlockMac && swift test --filter BiometricVaultEnvelopeTests`

Expected: FAIL，类型未定义。

- [ ] **Step 3: 实现固定 84 字节格式**

```text
0..3   magic "PWLB"
4      version 1
5..7   reserved 0
8..23  vault UUID raw bytes
24..35 nonce (12)
36..67 ciphertext (32)
68..83 tag (16)
```

使用 `bytes[0..<36]`（固定头、Vault ID、nonce）作为 AAD；严格验证长度、魔数、版本、保留位、预期 Vault ID、两个 Key 均为 32 字节。公开 API：

```swift
public static func seal(vaultKey: Data, wrappingKey: Data, vaultID: UUID, nonce: Data) throws -> Data
public static func open(_ data: Data, wrappingKey: Data, expectedVaultID: UUID) throws -> Data
public static func saveAtomically(_ data: Data, to url: URL) throws
```

保存使用同级临时文件、`FileHandle.synchronize()`、`rename` 和父目录 `fsync`；目标存在时原子替换。

- [ ] **Step 4: 运行测试确认 GREEN**

Run: `cd platforms/macos/PwdlockMac && swift test --filter BiometricVaultEnvelopeTests`

Expected: PASS。

- [ ] **Step 5: 提交该原子变更**

```bash
git add platforms/macos/PwdlockMac/Sources/PwdlockCore/Security/BiometricVaultEnvelope.swift platforms/macos/PwdlockMac/Tests/PwdlockCoreTests/BiometricVaultEnvelopeTests.swift
git commit -m "feat(mac): add biometric vault envelope"
```

### Task 2: 封装 Touch ID 与 Keychain

**Files:**
- Create: `platforms/macos/PwdlockMac/Sources/PwdlockCore/Application/BiometricAuthenticator.swift`
- Create: `platforms/macos/PwdlockMac/Sources/PwdlockCore/Security/BiometricKeyStore.swift`
- Create: `platforms/macos/PwdlockMac/Tests/PwdlockCoreTests/BiometricKeyStoreTests.swift`

- [ ] **Step 1: 写失败测试固定可替换接口和错误分类**

```swift
@Test("in-memory biometric key store creates reads and deletes one key")
func biometricKeyStoreContract() throws {
    let store = InMemoryBiometricKeyStore()
    try store.create(Data(repeating: 7, count: 32), vaultID: testVaultID)
    #expect(try store.read(vaultID: testVaultID, context: nil) == Data(repeating: 7, count: 32))
    try store.delete(vaultID: testVaultID)
    #expect(throws: BiometricKeyStoreError.notFound) { try store.read(vaultID: testVaultID, context: nil) }
}
```

- [ ] **Step 2: 运行测试确认 RED**

Run: `cd platforms/macos/PwdlockMac && swift test --filter BiometricKeyStoreTests`

Expected: FAIL，协议与错误类型未定义。

- [ ] **Step 3: 定义认证协议**

```swift
public enum BiometricAuthenticationResult: Equatable, Sendable { case success, cancelled, failed }

public protocol BiometricAuthenticating: AnyObject {
    var isTouchIDAvailable: Bool { get }
    func authenticate(reason: String, completion: @escaping @Sendable (BiometricAuthenticationResult) -> Void)
    func cancel()
}
```

`LocalAuthenticationAuthenticator` 使用 `LAPolicy.deviceOwnerAuthenticationWithBiometrics`，并要求 `biometryType == .touchID`；`LAError.userCancel`、`.appCancel`、`.systemCancel` 映射为 `.cancelled`，其余为 `.failed`。`cancel()` 调用当前 `LAContext.invalidate()`。

- [ ] **Step 4: 定义 Keychain 协议与系统实现**

```swift
public protocol BiometricKeyStoring: Sendable {
    func create(_ key: Data, vaultID: UUID) throws
    func read(vaultID: UUID, context: LAContext?) throws -> Data
    func delete(vaultID: UUID) throws
    func contains(vaultID: UUID) -> Bool
}
```

`KeychainBiometricKeyStore` 使用 Generic Password，service 为 `com.pwdlock.mac.biometric-wrap-key`，account 为小写 Vault UUID。创建 `SecAccessControlCreateWithFlags(kCFAllocatorDefault, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, [.biometryCurrentSet], nil)`；查询读取传入 `kSecUseAuthenticationContext`，禁用交互的 `contains` 查询使用 `kSecUseAuthenticationUIFail`。重复项、未找到和认证失效映射为稳定错误，不输出 OSStatus 或密钥。

- [ ] **Step 5: 运行测试与构建确认 GREEN**

Run: `cd platforms/macos/PwdlockMac && swift test --filter BiometricKeyStoreTests && swift build`

Expected: PASS 且构建成功；访问控制固定为 `.biometryCurrentSet` 与 `WhenPasscodeSetThisDeviceOnly`。

- [ ] **Step 6: 提交该原子变更**

```bash
git add platforms/macos/PwdlockMac/Sources/PwdlockCore/Application/BiometricAuthenticator.swift platforms/macos/PwdlockMac/Sources/PwdlockCore/Security/BiometricKeyStore.swift platforms/macos/PwdlockMac/Tests/PwdlockCoreTests/BiometricKeyStoreTests.swift
git commit -m "feat(mac): wrap Touch ID and Keychain access"
```

### Task 3: 将快捷材料生命周期接入 VaultSession

**Files:**
- Modify: `platforms/macos/PwdlockMac/Sources/PwdlockCore/Application/VaultSession.swift`
- Modify: `platforms/macos/PwdlockMac/Tests/PwdlockCoreTests/VaultSessionTests.swift`

- [ ] **Step 1: 写失败测试覆盖启用、关闭和解锁来源**

```swift
@Test("only a master-password session can enable Touch ID")
func enablesBiometricUnlockAfterMasterPassword() throws {
    let fixture = try BiometricSessionFixture.createdAndLocked()
    try fixture.session.unlock(masterPassword: fixture.password)
    try fixture.session.enableBiometricUnlock()
    #expect(fixture.session.isBiometricUnlockConfigured)
    fixture.session.lock()
    try fixture.session.unlockWithBiometrics(context: nil)
    #expect(fixture.session.unlockMethod == .biometric)
    #expect(throws: VaultSessionError.masterPasswordUnlockRequired) { try fixture.session.enableBiometricUnlock() }
}
```

另测关闭后两份材料都消失、修改主密码清理材料、包装损坏时清理并保持锁定、首次导入和本地备份不携带材料。

- [ ] **Step 2: 运行测试确认 RED**

Run: `cd platforms/macos/PwdlockMac && swift test --filter enablesBiometricUnlockAfterMasterPassword`

Expected: FAIL，API 未定义。

- [ ] **Step 3: 注入 KeyStore 并追踪解锁来源**

```swift
public enum VaultUnlockMethod: Equatable, Sendable { case masterPassword, biometric }
public private(set) var unlockMethod: VaultUnlockMethod?
public var isBiometricUnlockConfigured: Bool { /* key item 与文件同时存在 */ }
public func enableBiometricUnlock() throws
public func disableBiometricUnlock() throws
public func unlockWithBiometrics(context: LAContext?) throws
```

构造器增加默认 `KeychainBiometricKeyStore` 和 randomness 注入。主密码 `unlock` 成功设 `.masterPassword`；锁定清空。启用时生成 32 字节 Key，先写 Keychain，再包装当前 Vault Key 并原子写 `vault.biometric`；失败时删除两份本次材料。关闭删除两份材料，缺失视为成功。

- [ ] **Step 4: 实现快捷解锁和损坏收敛**

`unlockWithBiometrics` 从 metadata 推导 Vault UUID，使用同一 `LAContext` 读取 Keychain Key，读 `vault.biometric`、认证解包 Vault Key、打开 SQLCipher，成功后设 `.biometric`。Keychain 失效、Vault ID 不符、文件损坏、AES 认证失败时调用 `disableBiometricUnlock()` 并抛统一 `biometricUnlockFailed`；用户取消在认证器层终止，不能调用此 API，因此不清理材料。

- [ ] **Step 5: 修改主密码后清理**

在 `metadataStore.save(replacementMetadata)` 成功后调用 `disableBiometricUnlock()`；若清理失败，主密码修改仍成功，但返回可恢复的 `biometricCleanupFailed` 供 UI 提示重新检查设置。备份逻辑继续只复制 `vault.db`，导出只序列化登录项。

- [ ] **Step 6: 运行会话测试确认 GREEN**

Run: `cd platforms/macos/PwdlockMac && swift test --filter VaultSessionTests`

Expected: PASS。

- [ ] **Step 7: 提交该原子变更**

```bash
git add platforms/macos/PwdlockMac/Sources/PwdlockCore/Application/VaultSession.swift platforms/macos/PwdlockMac/Tests/PwdlockCoreTests/VaultSessionTests.swift
git commit -m "feat(mac): manage biometric unlock lifecycle"
```

### Task 4: 实现 AppState 自动提示一次与手动重试

**Files:**
- Modify: `platforms/macos/PwdlockMac/Sources/PwdlockMacApp/VaultAppState.swift`
- Modify: `platforms/macos/PwdlockMac/Tests/PwdlockMacAppTests/VaultAppStateTests.swift`

- [ ] **Step 1: 写失败测试覆盖自动一次、取消和手动重试**

```swift
@Test("unlock screen automatically offers Touch ID only once per lock cycle")
@MainActor func automaticallyPromptsTouchIDOnce() throws {
    let authenticator = FakeBiometricAuthenticator(available: true)
    let fixture = try BiometricAppStateFixture(configured: true, authenticator: authenticator)
    fixture.state.beginUnlockScreenIfNeeded()
    fixture.state.beginUnlockScreenIfNeeded()
    #expect(authenticator.requestCount == 1)
    authenticator.complete(.cancelled)
    #expect(fixture.state.screen == .unlock)
    #expect(fixture.state.canUseTouchID)
    fixture.state.retryTouchID()
    #expect(authenticator.requestCount == 2)
}
```

另测成功进入 library、失败显示通用中文提示、主密码入口不受影响、后台取消认证、重新锁定后新一轮可再自动提示一次。

- [ ] **Step 2: 运行测试确认 RED**

Run: `cd platforms/macos/PwdlockMac && swift test --filter automaticallyPromptsTouchIDOnce`

Expected: FAIL，状态和动作未定义。

- [ ] **Step 3: 添加状态和协调逻辑**

```swift
@Published private(set) var canUseTouchID = false
@Published private(set) var isTouchIDEnabled = false
@Published private(set) var isTouchIDAuthenticating = false
private var didAutomaticallyPromptTouchID = false

func beginUnlockScreenIfNeeded()
func retryTouchID()
func setTouchIDEnabled(_ enabled: Bool)
```

`beginUnlockScreenIfNeeded` 同时满足 unlock 页面、设备可用、材料齐全、尚未自动尝试时调用认证。成功后执行 `session.unlockWithBiometrics(context:)` 并进入 library；取消不显示错误；失败显示“Touch ID 无法完成验证，请使用主密码”。`resetLockedState()` 重置自动标志并刷新能力。

- [ ] **Step 4: 后台取消与主密码回退**

`applicationDidEnterBackground()` 先调用 `authenticator.cancel()`、清除 `isTouchIDAuthenticating`，再执行当前自动锁定逻辑。主密码 `unlock` 保持原限速逻辑，不与 Touch ID 失败共享计数器。

- [ ] **Step 5: 运行 AppState 测试确认 GREEN**

Run: `cd platforms/macos/PwdlockMac && swift test --filter VaultAppStateTests`

Expected: PASS。

- [ ] **Step 6: 提交该原子变更**

```bash
git add platforms/macos/PwdlockMac/Sources/PwdlockMacApp/VaultAppState.swift platforms/macos/PwdlockMac/Tests/PwdlockMacAppTests/VaultAppStateTests.swift
git commit -m "feat(mac): coordinate automatic Touch ID unlock"
```

### Task 5: 添加中文 Touch ID 界面

**Files:**
- Modify: `platforms/macos/PwdlockMac/Sources/PwdlockMacApp/VaultViews.swift`
- Modify: `platforms/macos/PwdlockMac/Tests/PwdlockMacAppTests/VaultViewsLayoutTests.swift`

- [ ] **Step 1: 写失败静态 UI 测试**

```swift
@Test("Touch ID controls preserve the master password path")
func touchIDUIContract() throws {
    let source = try String(contentsOf: vaultViewsURL, encoding: .utf8)
    #expect(source.contains("使用 Touch ID 解锁"))
    #expect(source.contains("启用 Touch ID 快捷解锁"))
    #expect(source.contains("SecureField(\"主密码\""))
    #expect(source.contains("Button(\"解锁\""))
}
```

- [ ] **Step 2: 运行测试确认 RED**

Run: `cd platforms/macos/PwdlockMac && swift test --filter touchIDUIContract`

Expected: FAIL，Touch ID 控件不存在。

- [ ] **Step 3: 修改解锁页**

`UnlockVaultView` 在出现时调用 `beginUnlockScreenIfNeeded()`；当 `canUseTouchID` 时显示带 `touchid` SF Symbol 的“使用 Touch ID 解锁”按钮，认证中禁用并显示 `ProgressView`。现有主密码 SecureField 和“解锁”按钮始终渲染。

- [ ] **Step 4: 修改设置菜单**

设备支持 Touch ID 时在设置菜单加入 `Toggle("启用 Touch ID 快捷解锁", isOn: ...)`。只有 `.masterPassword` 会话允许从关闭切到开启；若当前为 Touch ID 会话，开关关闭仍可执行，开启则由 AppState 显示“请先使用主密码解锁后再启用 Touch ID”。

- [ ] **Step 5: 运行测试和 debug 构建确认 GREEN**

Run: `cd platforms/macos/PwdlockMac && swift test && swift build`

Expected: 全部 PASS，构建成功。

- [ ] **Step 6: 提交该原子变更**

```bash
git add platforms/macos/PwdlockMac/Sources/PwdlockMacApp/VaultViews.swift platforms/macos/PwdlockMac/Tests/PwdlockMacAppTests/VaultViewsLayoutTests.swift
git commit -m "feat(mac): add Chinese Touch ID controls"
```

### Task 6: 安全验证与实机验收

**Files:**
- Modify only if verification exposes a scoped defect.

- [ ] **Step 1: 完整自动化验证**

Run: `cd platforms/macos/PwdlockMac && swift test`

Expected: 所有测试 PASS。

- [ ] **Step 2: release 构建**

Run: `cd platforms/macos/PwdlockMac && swift build -c release`

Expected: `Build complete!`。

- [ ] **Step 3: 检查产物不包含敏感材料**

创建临时密码库并启用 Touch ID 后，确认私有目录只有 `vault.biometric` 包装文件而没有明文 Key；创建本地备份并导出 `.pwdlock`，搜索归档内容与数据库备份流程，确认没有复制 `vault.biometric`；锁定后仓储访问抛 `.locked`。

- [ ] **Step 4: 实机 Touch ID 验收**

在带 Touch ID 的 Mac 上验证：首次启用要求主密码会话；锁定后自动弹一次；取消后不循环弹出且按钮可重试；成功进入同一密码库；后台时取消；增删指纹后自动回退主密码并清理材料；修改主密码和关闭开关都使下次不再提示。

- [ ] **Step 5: 完成后才重建 DMG**

复用仓库现有打包脚本/命令生成 `platforms/macos/PwdlockMac/dist/Pwdlock-macOS-arm64.dmg`，随后执行 `codesign --verify --deep --strict`、`spctl -a -vv`（自签名预期可能不被 Gatekeeper 信任，但签名结构必须有效）和 `hdiutil verify`。
