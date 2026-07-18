package com.pwdlock.android.data.network

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.nio.charset.StandardCharsets

/**
 * 在线同步服务（serve）的轻量 HTTP 客户端。
 *
 * 仅依赖内置 `java.net.HttpURLConnection` + `org.json`，零额外网络依赖。
 * 所有方法均为 `suspend`，在 [Dispatchers.IO] 执行。baseUrl 形如 `http://10.0.2.2:3000/v1`。
 */
class ApiClient(private val baseUrl: String) {
    private val root = baseUrl.trimEnd('/')

    private fun connect(path: String, method: String, token: String?, body: JSONObject?): HttpURLConnection {
        val url = URL("$root/$path")
        val conn = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = method
            setRequestProperty("Content-Type", "application/json; charset=utf-8")
            setRequestProperty("Accept", "application/json")
            connectTimeout = 15_000
            readTimeout = 30_000
            if (token != null) setRequestProperty("Authorization", "Bearer $token")
            if (body != null) {
                doOutput = true
                val bytes = body.toString().toByteArray(StandardCharsets.UTF_8)
                outputStream.write(bytes)
            }
        }
        return conn
    }

    private fun readJson(conn: HttpURLConnection): JSONObject? {
        val code = conn.responseCode
        when {
            code in 200..299 -> {
                if (code == 204) return null
                val text = conn.inputStream.bufferedReader(StandardCharsets.UTF_8).use { it.readText() }
                return if (text.isBlank()) null else JSONObject(text)
            }
            code == 401 -> throw ApiException.TokenExpired()
            code == 409 -> throw ApiException.Conflict(conn.errorMessage())
            else -> throw ApiException.HttpError(code, conn.errorMessage())
        }
    }

    private fun readJsonArray(conn: HttpURLConnection): JSONArray {
        val code = conn.responseCode
        return when {
            code in 200..299 -> {
                val text = conn.inputStream.bufferedReader(StandardCharsets.UTF_8).use { it.readText() }
                JSONArray(text)
            }
            code == 401 -> throw ApiException.TokenExpired()
            code == 409 -> throw ApiException.Conflict(conn.errorMessage())
            else -> throw ApiException.HttpError(code, conn.errorMessage())
        }
    }

    private fun HttpURLConnection.errorMessage(): String = try {
        val text = errorStream?.bufferedReader(StandardCharsets.UTF_8)?.use { it.readText() } ?: ""
        if (text.isBlank()) "HTTP $responseCode" else text
    } catch (_: Exception) {
        "HTTP $responseCode"
    }

    // region 认证

    suspend fun register(loginName: String, password: String): String = withContext(Dispatchers.IO) {
        val body = JSONObject().put("loginName", loginName).put("password", password)
        val conn = connect("auth/register", "POST", null, body)
        val json = readJson(conn) ?: throw ApiException.HttpError(500, "empty register response")
        json.getString("accessToken")
    }

    suspend fun login(loginName: String, password: String): String = withContext(Dispatchers.IO) {
        val body = JSONObject().put("loginName", loginName).put("password", password)
        val conn = connect("auth/login", "POST", null, body)
        val json = readJson(conn) ?: throw ApiException.HttpError(500, "empty login response")
        json.getString("accessToken")
    }

    // endregion

    // region 设备

    suspend fun registerDevice(label: String, publicSigningKey: String, token: String): OnlineDevice =
        withContext(Dispatchers.IO) {
            val body = JSONObject().put("label", label).put("publicSigningKey", publicSigningKey)
            val conn = connect("devices", "POST", token, body)
            val json = readJson(conn) ?: throw ApiException.HttpError(500, "empty device response")
            OnlineDevice(
                id = json.getString("id"),
                publicSigningKey = json.optString("publicSigningKey", ""),
                label = json.optString("label", ""),
                revokedAt = json.optString("revokedAt", ""),
            )
        }

    suspend fun listDevices(token: String): List<OnlineDevice> = withContext(Dispatchers.IO) {
        val conn = connect("devices", "GET", token, null)
        val arr = readJsonArray(conn)
        List(arr.length()) { i ->
            val o = arr.getJSONObject(i)
            OnlineDevice(
                id = o.getString("id"),
                publicSigningKey = o.optString("publicSigningKey", ""),
                label = o.optString("label", ""),
                revokedAt = o.optString("revokedAt", ""),
            )
        }
    }

    // endregion

    // region 保险库

    suspend fun createVault(encryptedKeyEnvelope: String, token: String): OnlineVault =
        withContext(Dispatchers.IO) {
            val body = JSONObject().put("encryptedKeyEnvelope", encryptedKeyEnvelope)
            val conn = connect("vaults", "POST", token, body)
            val json = readJson(conn) ?: throw ApiException.HttpError(500, "empty vault response")
            OnlineVault(
                id = json.getString("id"),
                encryptedKeyEnvelope = json.getString("encryptedKeyEnvelope"),
            )
        }

    suspend fun listVaults(token: String): List<OnlineVault> = withContext(Dispatchers.IO) {
        val conn = connect("vaults", "GET", token, null)
        val arr = readJsonArray(conn)
        List(arr.length()) { i ->
            val o = arr.getJSONObject(i)
            OnlineVault(
                id = o.getString("id"),
                encryptedKeyEnvelope = o.getString("encryptedKeyEnvelope"),
            )
        }
    }

    // endregion

    // region 变更

    suspend fun appendChange(
        vaultId: String,
        changeId: String,
        deviceId: String,
        envelope: OnlineSyncEnvelopeWire,
        token: String,
    ) = withContext(Dispatchers.IO) {
        val body = JSONObject()
            .put("changeId", changeId)
            .put("deviceId", deviceId)
            .put("ciphertext", envelope.ciphertext)
            .put("signature", envelope.signature)
        val conn = connect("vaults/$vaultId/changes", "POST", token, body)
        readJson(conn) // 201，返回已存记录；忽略内容
    }

    suspend fun listChanges(vaultId: String, after: String?, token: String): List<OnlineRemoteChange> =
        withContext(Dispatchers.IO) {
            val path = if (after != null) "vaults/$vaultId/changes?after=$after" else "vaults/$vaultId/changes"
            val conn = connect(path, "GET", token, null)
            val arr = readJsonArray(conn)
            List(arr.length()) { i ->
                val o = arr.getJSONObject(i)
                OnlineRemoteChange(
                    sequence = o.getString("sequence"),
                    vaultId = o.getString("vaultId"),
                    changeId = o.getString("changeId"),
                    deviceId = o.getString("deviceId"),
                    ciphertext = o.getString("ciphertext"),
                    signature = o.getString("signature"),
                )
            }
        }

    // endregion

    companion object {
        private const val TAG = "ApiClient"
        fun logError(t: Throwable) = Log.e(TAG, "network error", t)
    }
}

/** 上传变更时的线格式（与请求体字段一一对应）。 */
data class OnlineSyncEnvelopeWire(val ciphertext: String, val signature: String)
