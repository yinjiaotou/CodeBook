# Pwdlock 三端阶段性实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement each approved phase task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 以 macOS → Windows → Android 的顺序，交付无服务端、端侧全加密、可互操作的原生密码管理应用。

**Architecture:** 每端独立使用原生 UI 与受审计的密码学/数据库库；不共享运行时代码，也不建设服务端。三端只共享版本化 `.pwdlock` 协议、测试向量和验收矩阵，以保证文件级互操作。

**Tech Stack:** macOS—SwiftUI、CryptoKit、SQLite/SQLCipher、Argon2id；Windows—WinUI 3、.NET、SQLite/SQLCipher、Argon2id；Android—Jetpack Compose、Room/SQLCipher、Android Keystore、Argon2id。

---

## 交付顺序与完成原则

- 每个阶段均完成代码、自动化测试、手工安全走查和验收记录后，才启动下一阶段。
- 不实现云同步、账号、浏览器扩展、TOTP、附件或支付卡。
- 不自行实现 AES-GCM、Argon2id 或安全随机数；所有密钥与密码不写日志。
- 所有端均以本地私有目录保存 `vault.meta` 和 SQLCipher 数据库；写入采用临时文件、fsync 与原子替换。

## Phase 0：跨端安全基线与测试资产

**目标：** 在 UI 开发前锁定无法更改的协议和安全契约，避免三端各自解释格式。

**产出：**

- `docs/protocol/pwdlock-v1.md`：`.pwdlock` 外层、AAD、JSON schema、KDF 上下限与错误语义。
- `docs/protocol/vault-meta-v1.md`：`vault.meta` 的字节布局、AAD 与拒绝条件。
- `test-vectors/`：主密码包装、导出加密、错误密码、篡改头部、截断、尾随字节、超长长度与非法 JSON 测试向量。
- `docs/acceptance/security-checklist.md`：密钥生命周期、日志审查、原子写入、锁定与剪贴板检查表。

- [ ] 固化字段的字节序、长度和版本拒绝规则。
- [ ] 生成可公开分发但不含真实密钥/密码的测试向量。
- [ ] 明确三端统一错误：认证失败只显示“密码错误或文件损坏”。
- [ ] 评审并冻结 v1；后续变更只能通过新版本演进。

**完成门槛：** 三端实现者可只依赖测试资产开发互操作代码，无需猜测协议。

## Phase 1：macOS 安全 MVP

**目标：** 先验证完整密钥生命周期、本地加密库和崩溃恢复。

**范围：**

- SwiftUI 应用壳、首次创建主密码、解锁、锁定、修改主密码。
- 使用 `SecRandomCopyBytes` 生成 Vault Key、盐与 nonce；使用 Argon2id 派生 KEK，CryptoKit `AES.GCM` 包装 Vault Key。
- SQLCipher 密封本地 SQLite 数据库；仅将原始 32 字节 Vault Key 传入受支持的二进制密钥接口。
- 登录项的创建、查看、遮蔽/显示、复制、编辑、删除、搜索与分类。
- 后台遮蔽、3/5/10 分钟自动锁定、关闭数据库连接、30 秒剪贴板清除。
- 本地可验证备份恢复；不包含跨端 `.pwdlock` 导入导出。

- [ ] 创建 Xcode 项目、Swift Package 依赖与最小 CI 构建。
- [ ] 先对元数据编解码、KDF 输入规范化、包装/解包与原子写入编写单元测试。
- [ ] 实现 `VaultMetaStore`、`VaultKeyService`、`EncryptedDatabase` 和 `VaultRepository`。
- [ ] 实现解锁状态机、自动锁定与剪贴板服务。
- [ ] 实现 SwiftUI 密码库、条目详情与编辑流。
- [ ] 进行错误密码、元数据篡改、写入中断和锁定后数据不可读的回归测试。

**完成门槛：** 在 macOS 上可以安全创建、重启后解锁、管理条目、自动锁定，并从本地备份恢复。

## Phase 2：Windows 安全 MVP

**目标：** 以 Phase 1 的安全行为为基准，完成 Windows 原生实现。

**范围：** 与 macOS MVP 同等功能；使用 WinUI 3、.NET `RandomNumberGenerator`、受审计 Argon2id 库、受支持 AES-GCM API、SQLite/SQLCipher 与 `%LocalAppData%` 私有目录。

- [ ] 建立 WinUI 3/MSIX 项目、单元测试项目与依赖版本锁定。
- [ ] 对 `vault.meta`、主密码包装、原子写入和错误语义执行 Phase 0 测试向量。
- [ ] 实现加密数据库、仓储、锁定和剪贴板服务。
- [ ] 实现三栏管理界面、条目 CRUD、搜索、分类与本地备份恢复。
- [ ] 手工验证后台遮蔽、自动锁定和崩溃恢复。

**完成门槛：** Windows 输出与验证的 Vault 元数据行为与 macOS 相同，MVP 功能一致。

## Phase 3：Android 安全 MVP

**目标：** 完成 Android 原生端的同等安全 MVP，并遵循移动端后台限制。

**范围：** Jetpack Compose、Room/SQLCipher、`SecureRandom`、Android Keystore 的包装材料存放、Android 私有目录、后台遮蔽和 `FLAG_SECURE`。

- [ ] 建立 Android 项目、仪器测试与依赖版本锁定。
- [ ] 运行 Phase 0 测试向量，校验 NFC 标准化、字节序和认证失败语义。
- [ ] 实现本地加密数据库、解锁状态机、自动锁定、剪贴板服务和后台遮蔽。
- [ ] 实现移动端密码库、条目 CRUD、搜索、分类、复制倒计时和本地恢复。
- [ ] 验证 `FLAG_SECURE`、后台最近任务遮蔽与锁定后数据库关闭。

**完成门槛：** Android MVP 与桌面端具备相同的核心用户任务和安全边界。

## Phase 4：`.pwdlock` v1 备份、导入与互操作

**目标：** 在三个 MVP 都稳定后增加加密导出、导入和明确的冲突处理。

**范围：** 独立导出密码、Export Key、100 MiB 文件上限、认证后 JSON 解析、事务合并、冲突组与墓碑。

- [ ] 每端实现导出：独立导出密码、Argon2id、AES-GCM、临时写入、重新解密验证与原子替换。
- [ ] 每端实现导入预检：仅解析固定头，验证版本、长度、KDF 上限和保留位。
- [ ] 实现认证后载荷验证、数据库事务合并、墓碑与冲突组保存。
- [ ] 实现导入摘要和冲突裁决；密码默认遮蔽，禁止静默覆盖。
- [ ] 运行 3×3 导出/导入矩阵与篡改/截断/错误密码回归测试。

**完成门槛：** 任一平台导出的 v1 文件可被另两个平台导入，并且所有异常输入安全拒绝。

## Phase 5：体验增强与平台能力

**目标：** 不改变协议前提下完善日常体验。

- [ ] 强密码生成器、弱密码/重复密码检测和安全建议。
- [ ] macOS Touch ID、Windows Hello、Android BiometricPrompt 作为可选快捷解锁；生物识别只保护已有的本地包装材料。
- [ ] 分类管理、备份提醒、导入/导出结果摘要和无障碍优化。
- [ ] 各端安全文案与不可恢复提醒统一。

**完成门槛：** 体验功能不降低既有 KDF 参数、不会默认复用主密码作为导出密码，且不改变跨端文件格式。

## Phase 6：发布准备与独立审计

**目标：** 将可运行产品提升为可发布的安全产品。

- [ ] 固定所有密码学与 SQLCipher 依赖版本，生成 SBOM 和第三方许可清单。
- [ ] 自动化跑完所有测试向量、平台单测、互操作矩阵和异常写入测试。
- [ ] 完成独立密码学/安全审计、问题修复和复审。
- [ ] 准备隐私说明、威胁模型、恢复不可用声明、签名与安装包流程。

**完成门槛：** 通过第 13 节发布门槛：无高危未修复项、测试向量齐备、三端互操作已验证、文档准确。

## 下一步

按本计划，下一项是 Phase 0。Phase 0 完成并经确认后，开始 Phase 1 的 macOS MVP；Windows 与 Android 不并行启动，以便优先复用已验证的协议和验收经验。
