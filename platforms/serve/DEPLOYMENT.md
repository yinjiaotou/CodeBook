# Pwdlock `serve` 服务迁移与服务器部署指南

本文说明如何将本目录中的 NestJS 同步服务迁移到 Ubuntu 云服务器、连接现有 PostgreSQL，并作为长期运行的 `systemd` 服务对客户端提供 API。文中的示例与当前线上部署保持一致：应用目录为 `/home/pwd-serve`，服务名为 `pwdlock-serve`，端口为 `3000`，API 前缀为 `/v1`。

> 当前客户端使用 `http://<服务器公网 IP>:3000/v1`。HTTP 会明文传输登录密码，只适合临时测试。正式发布前应使用域名、Nginx/Caddy 和 HTTPS，并将客户端地址切换到 HTTPS。

## 1. 部署边界与前提

服务只存储账户密码的 Argon2id 哈希、客户端生成的加密密钥信封、变更密文和签名；它不应接收主密码、Vault Key 或任何密码条目明文。

准备以下条件：

- 一台可通过 SSH 访问的 Ubuntu 服务器（下文以 `root@<服务器公网 IP>` 为例）。
- 可连接的 PostgreSQL 16 数据库；数据库端口 `5432` 不应暴露到公网。
- 服务器上 Node.js 22、npm、PostgreSQL 客户端 `psql`。当前线上服务使用 Node.js `v22.22.2`。
- 云厂商安全组允许入站 TCP `3000`；SSH 的 `22` 仅向可信来源开放。
- 一段至少 32 字符的随机 `JWT_SECRET`。生成示例：`openssl rand -base64 48`。

不要将 `.env`、数据库连接串、JWT 密钥或客户端令牌提交到 Git、上传到网盘或写入终端截图。

## 2. 首次迁移代码到服务器

以下在本机仓库根目录执行。命令不会传输本地依赖、构建产物和环境密钥：

```sh
rsync -az \
  --exclude node_modules \
  --exclude dist \
  --exclude .env \
  platforms/serve/ root@<服务器公网 IP>:/home/pwd-serve/
```

如果服务器目录不存在，先创建：

```sh
ssh root@<服务器公网 IP> 'mkdir -p /home/pwd-serve'
```

随后登录服务器并进入应用目录：

```sh
ssh root@<服务器公网 IP>
cd /home/pwd-serve
```

### 安装运行环境

确认版本：

```sh
node --version
npm --version
psql --version
```

如果 `node` 仅通过 NVM 安装，非交互 shell 和 `systemd` 默认不会加载 NVM。记录其绝对路径，后续将它写入服务单元：

```sh
command -v node
# 例如：/root/.nvm/versions/node/v22.22.2/bin/node
```

安装项目依赖并构建：

```sh
cd /home/pwd-serve
npm ci
npm run lint
npm test
npm run build
```

## 3. 配置生产环境变量

创建仅服务器管理员可读的 `/home/pwd-serve/.env`：

```dotenv
NODE_ENV=production
PORT=3000
DATABASE_URL=postgres://<数据库用户>:<数据库密码>@<数据库主机>:5432/<数据库名>?sslmode=require
JWT_SECRET=<至少 32 字符的随机密钥>
JWT_TTL_SECONDS=900
TYPEORM_SYNCHRONIZE=false
```

说明：

- 若 PostgreSQL 就运行在同一台服务器，数据库主机应为 `127.0.0.1`，而不是公网 IP。
- `sslmode=require` 适用于通常要求 TLS 的云数据库；若是服务器本地 PostgreSQL 且未启用 TLS，可按实际连接策略移除该参数。
- `TYPEORM_SYNCHRONIZE` 在共享、测试和生产数据库中始终保持 `false`。表结构只能由 SQL 迁移变更。

设置文件权限并做不泄密的检查：

```sh
chmod 600 /home/pwd-serve/.env
sed -E 's/=.*$/=<redacted>/' /home/pwd-serve/.env
```

## 4. 初始化或迁移 PostgreSQL

先加载连接串，不要把连接串直接粘贴到命令行参数中：

```sh
cd /home/pwd-serve
set -a
. ./.env
set +a
```

### 新数据库

按文件名顺序执行初始化 SQL 和全部迁移。`002` 使用了 `IF NOT EXISTS`，可以安全用于包含初始化表结构的新库：

```sh
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f db/init/001-initial-schema.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f db/migrations/002-add-device-revocation.sql
```

### 已存在的数据库

先备份，再确认已执行过哪些迁移；不要重复执行非幂等迁移。当前仓库的 `002-add-device-revocation.sql` 是幂等的，可重复运行：

```sh
pg_dump "$DATABASE_URL" --format=custom --file "/root/pwdlock-before-$(date +%F-%H%M%S).dump"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f db/migrations/002-add-device-revocation.sql
```

验证必要表存在：

```sh
psql "$DATABASE_URL" -c '\\dt'
```

## 5. 配置 systemd 常驻服务

新建 `/etc/systemd/system/pwdlock-serve.service`。将 `ExecStart` 中的 Node 路径替换为 `command -v node` 的实际输出；这是使用 NVM 时最容易遗漏的环节。

```ini
[Unit]
Description=Pwdlock sync service
After=network.target postgresql.service

[Service]
Type=simple
WorkingDirectory=/home/pwd-serve
Environment=NODE_ENV=production
EnvironmentFile=/home/pwd-serve/.env
ExecStart=/root/.nvm/versions/node/v22.22.2/bin/node /home/pwd-serve/dist/main.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

加载并启动：

```sh
systemctl daemon-reload
systemctl enable --now pwdlock-serve
systemctl status pwdlock-serve --no-pager
```

日常查看日志：

```sh
journalctl -u pwdlock-serve -f
journalctl -u pwdlock-serve -n 100 --no-pager
```

服务必须监听所有 IPv4 地址而非仅回环地址。当前实现已在 `src/main.ts` 中使用 `0.0.0.0`，可用下列命令确认：

```sh
ss -ltnp | grep ':3000'
# 期望包含：0.0.0.0:3000
```

## 6. 开放网络端口

需要同时满足以下三层条件：

1. 应用已经监听 `0.0.0.0:3000`。
2. 服务器防火墙允许 TCP 3000；例如启用了 UFW 时执行 `ufw allow 3000/tcp`。
3. 云厂商安全组/防火墙新增入站规则：协议 `TCP`、端口 `3000`、来源临时测试可为 `0.0.0.0/0`。

当前服务器主机侧 UFW 处于未启用状态；是否能从公网访问仍主要取决于云安全组。生产环境应尽快改为 `443` 上的 HTTPS，并关闭公网 `3000`。

## 7. 验证部署

先在服务器本机检查路由。根路径没有业务接口，返回 `404 Cannot GET /v1` 表示 NestJS 已在该前缀正常响应：

```sh
curl -i http://127.0.0.1:3000/v1
```

再从本机或另一台外部机器验证公网连通性：

```sh
curl -i http://<服务器公网 IP>:3000/v1
```

验证登录路由时使用不存在的测试账号和任意不少于 12 个字符的密码。预期 `401 Unauthorized`，这证明请求已经到达应用；不要在命令历史里使用真实账户密码：

```sh
curl -i -X POST "http://<服务器公网 IP>:3000/v1/auth/login" \
  -H 'Content-Type: application/json' \
  --data '{"loginName":"diagnostic","password":"invalid-password-123"}'
```

当前线上地址的验证结果应为：`/v1` 返回 `404`，`/v1/auth/login` 的错误账号返回 `401`。若出现连接超时或连接拒绝，按第 6 节依次检查监听地址、主机防火墙和云安全组。

## 8. 客户端切换与验收

macOS 客户端服务地址在 `platforms/macos/PwdlockMac/Sources/PwdlockMacApp/OnlineAccountState.swift`：

```swift
private let serviceURL = URL(string: "http://<服务器公网 IP>:3000/v1")!
```

纯 HTTP 还需要在 macOS App 的 `Resources/Info.plist` 中配置 `NSAppTransportSecurity/NSAllowsArbitraryLoads`，否则 URLSession 会被系统的 App Transport Security 拦截。修改地址或网络许可后必须重新构建并安装 DMG，已运行的旧 App 不会自动更新：

```sh
cd platforms/macos/PwdlockMac
./Scripts/build-dmg.sh
```

验收时先注册一个全新测试账号，再登录、创建在线密码库、创建第二个客户端并同步一条测试密码记录。确认后删除测试账号或使用独立测试数据库；不要用真实密码明文作为测试数据。

## 9. 后续版本更新与回滚

### 常规更新

先保留上一版构建产物和 `.env`，再上传新代码。不要用会删除服务器 `.env` 的同步参数。

```sh
cd /home/pwd-serve
systemctl stop pwdlock-serve
cp -a dist "dist.backup-$(date +%F-%H%M%S)"
npm ci
npm run lint
npm test
npm run build
# 如有新增 SQL 迁移，先备份数据库后按文件名顺序执行。
systemctl start pwdlock-serve
systemctl status pwdlock-serve --no-pager
```

### 应用回滚

若仅应用代码异常且数据库迁移未改变数据，可恢复上一份 `dist.backup-*`：

```sh
systemctl stop pwdlock-serve
mv dist dist.failed-$(date +%F-%H%M%S)
mv dist.backup-<时间戳> dist
systemctl start pwdlock-serve
```

数据库迁移不能仅通过回滚应用二进制撤销。涉及表结构或数据变更时，必须以迁移前的 `pg_dump` 备份和经过审核的反向 SQL 为准。

## 10. 运行检查清单

- `systemctl is-active pwdlock-serve` 输出 `active`。
- `ss -ltnp | grep ':3000'` 显示 `0.0.0.0:3000`。
- 公网 `POST /v1/auth/login` 能返回 HTTP 响应。
- 数据库 `5432` 未在云安全组公开。
- `.env` 权限为 `600`，未进入 Git。
- `TYPEORM_SYNCHRONIZE=false`。
- 数据库有定期、可恢复的备份。
- 正式发布前已用 HTTPS 取代 HTTP，并重新打包客户端。
