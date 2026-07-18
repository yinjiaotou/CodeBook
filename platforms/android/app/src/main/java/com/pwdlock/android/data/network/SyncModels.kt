package com.pwdlock.android.data.network

/** 服务端返回的资源模型（字段与 serve API 文档一致）。 */

data class TokenResponse(val accessToken: String)

data class OnlineDevice(
    val id: String,
    val publicSigningKey: String,
    val label: String = "",
    val revokedAt: String? = null,
)

data class OnlineVault(
    val id: String,
    val encryptedKeyEnvelope: String,
)

data class OnlineRemoteChange(
    val sequence: String,
    val vaultId: String,
    val changeId: String,
    val deviceId: String,
    val ciphertext: String,
    val signature: String,
)

/** 网络层异常。 */
sealed class ApiException(message: String) : Exception(message) {
    /** 401：令牌失效或登录失败，需重新登录。 */
    class TokenExpired : ApiException("unauthorized")

    /** 409：资源冲突（如账号已存在、changeId 被不同内容占用）。 */
    class Conflict(message: String) : ApiException(message)

    /** 其他非 2xx（含 400 参数错误）。 */
    class HttpError(val statusCode: Int, message: String) : ApiException("HTTP $statusCode: $message")
}
