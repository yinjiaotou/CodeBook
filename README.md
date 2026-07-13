# Pwdlock

三端原生、本地加密的密码管理器。平台运行时代码互不共享；跨端仅共享版本化协议与测试向量。

## 目录

- `platforms/macos/PwdlockMac`：Swift Package；SwiftUI 应用与安全核心。
- `platforms/windows`：未来的 WinUI 3 / .NET 工程。
- `platforms/android`：未来的 Jetpack Compose / Kotlin 工程。
- `shared/protocol`：`.pwdlock`、`vault.meta` 与载荷 schema 的规范。
- `shared/test-vectors`：三端共用的密码学和格式测试向量。
- `docs`：设计、实施计划与验收文档。

## 当前 macOS 验证

```sh
cd platforms/macos/PwdlockMac
swift test
```
