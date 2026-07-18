# Pwdlock 同步服务 API 文档

本文档对应当前 `serve` 服务实现。服务为端到端加密的密码库提供账户认证、设备登记与密文同步；不会接收或解析主密码、Vault Key 或任何密码条目明文。

相关的加密数据格式、签名内容和客户端处理规则见[在线同步协议](../../shared/protocol/online-sync-v1.md)。

## 基本约定

| 项目 | 说明 |
| --- | --- |
| 服务地址 | 本地默认 `http://localhost:3000` |
| API 前缀 | `/v1` |
| 编码 | 请求和响应均为 JSON，使用 `UTF-8` |
| 认证 | 除注册、登录外，均需 `Authorization: Bearer <accessToken>` |
| Token | JWT；默认有效期为 900 秒，可由 `JWT_TTL_SECONDS` 配置 |
| 字段校验 | 不接受未声明字段；多余字段会返回 `400` |
| 标识符 | 数据库生成的 `id`、`ownerId`、`deviceId`、`vaultId` 均为 UUID 字符串 |
| Base64 | 使用标准 Base64 字符集（`A-Z`、`a-z`、`0-9`、`+`、`/` 和 `=` 填充） |

下文所有路径均已包含 `/v1` 前缀。

## 通用响应与错误

成功响应直接返回对应资源或数组，没有统一的 `data` 外层包装。创建资源默认返回 `201 Created`，查询返回 `200 OK`，撤销设备返回 `204 No Content`。

异常采用 NestJS 默认 JSON 格式；`message` 在参数校验失败时可能是字符串数组：

```json
{
  "statusCode": 400,
  "message": ["password must be longer than or equal to 12 characters"],
  "error": "Bad Request"
}
```

常见状态码如下：

| 状态码 | 含义 |
| --- | --- |
| `400` | 请求 JSON、参数格式、长度或 Base64 格式不合法，或包含多余字段 |
| `401` | 缺少 Bearer Token、Token 无效/过期，或登录账号密码错误 |
| `403` | 当前账号无权访问密码库，或设备已撤销、不属于当前账号、签名无效 |
| `404` | 密码库或设备不存在，或设备不属于当前账号 |
| `409` | 注册的账号已存在，或 `changeId` 已被不同内容占用 |

## 认证

### 注册账号

`POST /v1/auth/register`

创建账号并立即返回访问令牌。`loginName` 在服务端会先去除首尾空白、再转为小写后存储和比较。

请求体：

| 字段 | 类型 | 必填 | 规则 |
| --- | --- | --- | --- |
| `loginName` | string | 是 | 长度 3–320；建议使用账号名或邮箱 |
| `password` | string | 是 | 长度 12–1024；仅用于服务账号认证，不能是密码库主密码 |

```json
{
  "loginName": "alice@example.com",
  "password": "a-service-account-password"
}
```

`201 Created`：

```json
{
  "accessToken": "<JWT>"
}
```

账号已存在时返回 `409`。

### 登录

`POST /v1/auth/login`

使用相同请求体获取新的访问令牌。

`200 OK`：

```json
{
  "accessToken": "<JWT>"
}
```

账号不存在或密码错误时均返回 `401`，不区分具体原因。

## 设备

本节全部接口都需要 Bearer Token。设备公钥为客户端生成的原始 32 字节 Ed25519 公钥，经 Base64 编码后传输。服务使用该公钥验证随后上传的变更签名。

### 登记设备

`POST /v1/devices`

请求体：

| 字段 | 类型 | 必填 | 规则 |
| --- | --- | --- | --- |
| `label` | string | 是 | 长度 1–120；服务会去除首尾空白 |
| `publicSigningKey` | string | 是 | 恰为 32 字节 Ed25519 公钥的 Base64 值，即 44 个字符、末尾一个 `=` |

```json
{
  "label": "Alice 的 Mac",
  "publicSigningKey": "<32-byte Ed25519 public key encoded in Base64>"
}
```

`201 Created`：

```json
{
  "id": "6ea88b3b-89ca-40c6-9b2d-d168c47e6c6e",
  "ownerId": "93e7281b-a1b7-4b0d-a3dc-df1738342477",
  "publicSigningKey": "<base64 public key>",
  "label": "Alice 的 Mac",
  "revokedAt": null
}
```

### 获取设备列表

`GET /v1/devices`

返回当前账号的全部设备（包括已撤销设备），按 `id` 升序排列。

`200 OK`：

```json
[
  {
    "id": "6ea88b3b-89ca-40c6-9b2d-d168c47e6c6e",
    "ownerId": "93e7281b-a1b7-4b0d-a3dc-df1738342477",
    "publicSigningKey": "<base64 public key>",
    "label": "Alice 的 Mac",
    "revokedAt": null
  }
]
```

`revokedAt` 为 `null` 表示可用；已撤销时为 ISO 8601 UTC 时间字符串。

### 撤销设备

`DELETE /v1/devices/:deviceID`

将当前账号名下的设备标记为已撤销。重复撤销同一设备也会成功；操作不会删除设备或其历史变更。

路径参数：

| 参数 | 类型 | 说明 |
| --- | --- | --- |
| `deviceID` | UUID string | 要撤销的当前账号设备 ID |

`204 No Content`

设备不存在或不属于当前账号时返回 `404`。被撤销设备不能再上传变更，但其已签署、已存储的变更仍可读取。

## 密码库

本节全部接口都需要 Bearer Token。服务仅保存客户端加密后的密钥信封和变更密文，不解密也不修改这些内容。

### 创建密码库

`POST /v1/vaults`

请求体：

| 字段 | 类型 | 必填 | 规则 |
| --- | --- | --- | --- |
| `encryptedKeyEnvelope` | string | 是 | 合法 Base64，长度 24–2,000,000；内容为客户端生成的加密 Vault Key 信封 |

```json
{
  "encryptedKeyEnvelope": "<base64 encrypted Vault Key envelope>"
}
```

`201 Created`：

```json
{
  "id": "c92e2870-9ca0-4624-804e-488e95b8e2c5",
  "ownerId": "93e7281b-a1b7-4b0d-a3dc-df1738342477",
  "encryptedKeyEnvelope": "<base64 encrypted Vault Key envelope>"
}
```

### 获取密码库列表

`GET /v1/vaults`

返回当前账号创建的全部密码库，按 `id` 升序排列。

`200 OK`：

```json
[
  {
    "id": "c92e2870-9ca0-4624-804e-488e95b8e2c5",
    "ownerId": "93e7281b-a1b7-4b0d-a3dc-df1738342477",
    "encryptedKeyEnvelope": "<base64 encrypted Vault Key envelope>"
  }
]
```

### 追加加密变更

`POST /v1/vaults/:vaultID/changes`

向当前账号拥有的密码库追加一条加密变更。上传前服务会确认设备属于当前账号且未撤销，并根据已登记的 Ed25519 公钥验证签名。

路径参数：

| 参数 | 类型 | 说明 |
| --- | --- | --- |
| `vaultID` | UUID string | 当前账号拥有的密码库 ID |

请求体：

| 字段 | 类型 | 必填 | 规则 |
| --- | --- | --- | --- |
| `changeId` | string | 是 | 长度 1–128；应由客户端生成全局唯一 ID。当前客户端使用小写 UUID。 |
| `deviceId` | UUID string | 是 | 已登记且未撤销、属于当前账号的设备 ID |
| `ciphertext` | string | 是 | 合法 Base64，长度 24–2,000,000；客户端加密变更信封 |
| `signature` | string | 是 | 合法 Base64，长度 24–16,384；通常为 64 字节 Ed25519 签名的 Base64 值 |

```json
{
  "changeId": "71b2eaa8-16a5-4477-ae2c-12bf109fae8d",
  "deviceId": "6ea88b3b-89ca-40c6-9b2d-d168c47e6c6e",
  "ciphertext": "<base64 encrypted change envelope>",
  "signature": "<base64 Ed25519 signature>"
}
```

签名消息的 UTF-8 字节序列严格为：

```text
pwdlock.sync.v1\0<lowercase vaultID>\0<lowercase changeId>\0<ciphertext>
```

其中 `\0` 是一个 NUL 字节；`ciphertext` 是传输中的 Base64 原文本，不是解码后的字节。服务在验签时将 `vaultID` 和 `changeId` 转为小写。因此客户端应以 UUID 的小写规范形式签名和提交。

`201 Created`：

```json
{
  "sequence": "42",
  "vaultId": "c92e2870-9ca0-4624-804e-488e95b8e2c5",
  "changeId": "71b2eaa8-16a5-4477-ae2c-12bf109fae8d",
  "deviceId": "6ea88b3b-89ca-40c6-9b2d-d168c47e6c6e",
  "ciphertext": "<base64 encrypted change envelope>",
  "signature": "<base64 Ed25519 signature>"
}
```

`sequence` 是服务端单调递增游标，以字符串返回，以免客户端 JSON 数字精度不足。

幂等规则：若 `changeId` 已存在，且其 `vaultId`、`deviceId`、`ciphertext`、`signature` 都与本次请求完全一致，服务返回既有记录和 `201`；任一字段不同则返回 `409`。已存在的完全相同变更不会再次进行设备或签名校验。

### 拉取加密变更

`GET /v1/vaults/:vaultID/changes?after=:sequence`

返回密码库变更，按 `sequence` 升序排列。服务只检查密码库所有权；不按设备撤销状态过滤历史记录。

路径参数：

| 参数 | 类型 | 说明 |
| --- | --- | --- |
| `vaultID` | UUID string | 当前账号拥有的密码库 ID |

查询参数：

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `after` | 十进制整数字符串 | 否 | 仅返回 `sequence` 严格大于此值的记录；省略时返回全部记录 |

`200 OK`：

```json
[
  {
    "sequence": "42",
    "vaultId": "c92e2870-9ca0-4624-804e-488e95b8e2c5",
    "changeId": "71b2eaa8-16a5-4477-ae2c-12bf109fae8d",
    "deviceId": "6ea88b3b-89ca-40c6-9b2d-d168c47e6c6e",
    "ciphertext": "<base64 encrypted change envelope>",
    "signature": "<base64 Ed25519 signature>"
  }
]
```

当前接口不提供分页大小参数或响应条数限制。客户端应保存最后收到的 `sequence`，下一次使用 `after` 增量拉取，并在本地解密、验签、排序、合并与处理冲突。

## 调用顺序示例

1. 调用注册或登录接口，保存返回的 `accessToken`。
2. 使用 Token 登记本设备的 Ed25519 公钥。
3. 创建密码库，上传客户端加密后的 Vault Key 信封。
4. 上传变更前，在客户端加密变更并使用本设备私钥签名。
5. 记录上传或拉取结果中的最大 `sequence`；后续以 `after` 进行增量同步。

生产环境必须通过 HTTPS 调用接口。不要在请求、日志、指标或错误消息中传递主密码、Vault Key、解密后的密码条目或私钥。
