# Pwdlock macOS Touch ID 快捷解锁设计

## 目标与安全边界

Touch ID 仅作为本机快捷解锁方式，不替代主密码，不参与 `.pwdlock` 导入导出，也不提供远程恢复。首次启用必须发生在用户使用主密码成功解锁之后。任何不可用、取消、指纹集合变化或本地材料损坏都回退到主密码。用户取消只结束本次认证，不删除仍然有效的快捷解锁材料；指纹集合变化或材料损坏才清理材料。

## 密钥结构

启用时生成随机 32 字节 Biometric Wrap Key。该密钥作为 Keychain Generic Password 保存，访问控制为仅限当前设备且绑定当前指纹集合；读取必须通过 `LAContext` 完成 Touch ID 验证。

当前 32 字节 Vault Key 使用 Biometric Wrap Key 经 AES-256-GCM 包装。包装文件 `vault.biometric` 位于密码库私有目录，包含固定魔数、版本、Vault ID、12 字节 nonce、32 字节密文和 16 字节标签；固定头与 Vault ID 作为 AAD。文件采用临时写入、fsync 和原子发布。

Keychain 中不保存主密码，`vault.biometric` 中不保存明文 Vault Key 或 Biometric Wrap Key。锁定时释放读取到的包装密钥和解开的 Vault Key 引用。

## 启用与关闭

- 设置页仅在设备支持 Touch ID 时显示开关。
- 只有最近一次通过主密码解锁的会话可以启用；Touch ID 解锁的会话不能自行重新建立快捷解锁材料。
- 启用时先创建受保护 Keychain 项，再写入包装文件；任一步失败时清理本次创建的材料并保持 Touch ID 关闭。
- 关闭时删除 Keychain 项和 `vault.biometric`；即使其中一项已不存在，也以关闭状态收敛。
- 修改主密码成功后删除 Touch ID 材料，用户下次用新主密码解锁后可重新启用。
- 本地备份、`.pwdlock` 导出与导入均不包含 Touch ID 材料；导入的新密码库默认关闭。

## 解锁流程

应用进入解锁页面时，如 Keychain 项与 `vault.biometric` 同时存在且设备支持 Touch ID，则自动发起一次验证：

1. `LAContext` 提示用户使用 Touch ID；
2. 验证成功后读取 Biometric Wrap Key；
3. 认证解开 Vault Key；
4. 使用 Vault Key 打开 SQLCipher 数据库并进入密码库；
5. 任一步失败时保持锁定并显示通用中文提示，主密码输入始终可用。

同一轮解锁页面只自动弹出一次，避免取消后循环弹窗。页面保留“使用 Touch ID 解锁”按钮，用户可再次主动触发。应用进入后台时取消正在进行的认证并维持锁定。

## 组件边界

- `BiometricAuthenticator`：封装 `LocalAuthentication` 能力检查和验证，支持测试替身。
- `BiometricKeyStore`：封装 Keychain 创建、读取与删除，不访问数据库。
- `BiometricVaultEnvelope`：负责 AES-GCM 包装文件编解码和认证，不调用 UI。
- `VaultSession`：在已解锁状态启用/关闭 Touch ID，并使用解开的 Vault Key 打开数据库。
- `VaultAppState`：管理自动提示一次、手动重试、设置开关和通用错误状态。
- SwiftUI：显示设置开关、Touch ID 按钮和状态；不接触密钥字节。

## 错误与恢复

- 用户取消：不显示敏感错误，停留在主密码页面。
- 验证失败或锁定：提示“Touch ID 无法完成验证，请使用主密码”。
- 指纹集合变化、Keychain 项失效、包装认证失败：删除快捷解锁材料并要求主密码重新启用。
- 设备不支持或未录入 Touch ID：隐藏设置开关和快捷按钮。
- 不记录 `LAError` 细节、密码、密钥、nonce、标签或数据库路径。

## 测试与验收

- 主密码解锁后可启用，Touch ID 解锁后不能重建材料；
- Keychain 项为仅限本机并绑定当前指纹集合；
- 包装/解包 round-trip，错误 Key、篡改头、nonce、密文和标签均拒绝；
- 解锁页每轮只自动提示一次，取消后主密码仍可用，手动按钮可重试；
- Touch ID 成功打开同一密码库，锁定后仓储不可访问；
- 修改主密码与关闭开关都会清理 Keychain 和包装文件；
- 指纹集合变化或材料损坏安全回退，不循环弹窗；
- 备份与 `.pwdlock` 文件中不存在 `vault.biometric` 或 Keychain 数据；
- 不支持 Touch ID 的测试环境保持主密码流程；
- 完整单测、release 构建、自签名 DMG 和实机 Touch ID 手工验证通过。
