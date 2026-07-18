package com.pwdlock.android.data.online

import com.pwdlock.android.data.model.PwdlockRecord
import org.json.JSONObject
import java.nio.charset.StandardCharsets

/**
 * 在线变更的 JSON 编解码，字段名严格对齐 macOS `LoginItem` / `OnlineVaultChange`：
 * - JSON 键使用小写驼峰，且 **无 `type` 字段**；
 * - 时间为毫秒数字（`createdAt` / `updatedAt`），设备标识为 `deviceID`（大写 D）。
 * 这与本地存储用的 `VaultJson`（键名 `createdAtMs` 等）不同，不可混用。
 */
data class OnlineVaultChange(
    val operation: String, // "upsert" | "delete"
    val record: PwdlockRecord,
    val previousChangeDigest: String? = null,
)

object OnlineChangeJson {
    fun encode(change: OnlineVaultChange): ByteArray {
        val r = change.record
        val item = JSONObject().apply {
            put("id", r.id)
            put("title", r.title)
            put("username", r.username)
            put("password", r.password)
            put("url", r.url)
            put("category", r.category)
            put("note", r.note)
            put("createdAt", r.createdAtMs)
            put("updatedAt", r.updatedAtMs)
            put("revision", r.revision)
            put("deviceID", r.deviceId)
        }
        val root = JSONObject().apply {
            put("operation", change.operation)
            put("item", item)
            put("previousChangeDigest", JSONObject.NULL)
        }
        return root.toString().toByteArray(StandardCharsets.UTF_8)
    }

    fun decode(bytes: ByteArray): OnlineVaultChange {
        val root = JSONObject(String(bytes, StandardCharsets.UTF_8))
        val item = root.getJSONObject("item")
        val record = PwdlockRecord(
            id = item.getString("id"),
            type = "login",
            title = item.optString("title", ""),
            username = item.optString("username", ""),
            password = item.optString("password", ""),
            url = item.optString("url", ""),
            category = item.optString("category", ""),
            note = item.optString("note", ""),
            createdAtMs = item.getLong("createdAt"),
            updatedAtMs = item.getLong("updatedAt"),
            revision = item.getLong("revision"),
            deviceId = item.getString("deviceID"),
        )
        return OnlineVaultChange(root.getString("operation"), record, null)
    }
}
