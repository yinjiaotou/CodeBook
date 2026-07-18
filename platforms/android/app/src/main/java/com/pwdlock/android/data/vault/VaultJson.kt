package com.pwdlock.android.data.vault

import com.pwdlock.android.data.model.PwdlockPayload
import com.pwdlock.android.data.model.PwdlockRecord
import com.pwdlock.android.data.model.PwdlockTombstone
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/**
 * `PwdlockPayload` 的 JSON 编解码（使用 Android 内置的 org.json）。
 *
 * - 字段名、键集合与 macOS 严格校验一致（可直接被 macOS 导入）。
 * - UUID 统一输出/解析为小写（Java `UUID.toString()` 本就是小写）。
 */
object VaultJson {
    fun encodePayload(p: PwdlockPayload): String {
        val root = JSONObject()
        root.put("schemaVersion", p.schemaVersion)
        root.put("exportId", p.exportId.toString())
        root.put("sourceVaultId", p.sourceVaultId.toString())
        root.put("createdAtMs", p.createdAtMs)
        val records = JSONArray()
        p.records.forEach { records.put(recordToJson(it)) }
        root.put("records", records)
        root.put("tombstones", JSONArray())
        root.put("conflictGroups", JSONArray())
        return root.toString()
    }

    fun decodePayload(json: String): PwdlockPayload {
        val root = JSONObject(json)
        val records = mutableListOf<PwdlockRecord>()
        val arr = root.getJSONArray("records")
        for (i in 0 until arr.length()) records.add(jsonToRecord(arr.getJSONObject(i)))

        val tombstones = mutableListOf<PwdlockTombstone>()
        if (root.has("tombstones")) {
            val t = root.getJSONArray("tombstones")
            for (i in 0 until t.length()) {
                val o = t.getJSONObject(i)
                tombstones.add(
                    PwdlockTombstone(
                        recordId = o.getString("recordId"),
                        deletedAtMs = o.getLong("deletedAtMs"),
                        revision = o.getLong("revision"),
                        deviceId = o.getString("deviceId"),
                    )
                )
            }
        }

        return PwdlockPayload(
            schemaVersion = root.optInt("schemaVersion", 1),
            exportId = UUID.fromString(root.getString("exportId")),
            sourceVaultId = UUID.fromString(root.getString("sourceVaultId")),
            createdAtMs = root.getLong("createdAtMs"),
            records = records,
            tombstones = tombstones,
        )
    }

    private fun recordToJson(r: PwdlockRecord): JSONObject = JSONObject().apply {
        put("id", r.id.lowercase())
        put("type", r.type)
        put("title", r.title)
        put("username", r.username)
        put("password", r.password)
        put("url", r.url)
        put("category", r.category)
        put("note", r.note)
        put("createdAtMs", r.createdAtMs)
        put("updatedAtMs", r.updatedAtMs)
        put("revision", r.revision)
        put("deviceId", r.deviceId.lowercase())
    }

    private fun jsonToRecord(o: JSONObject): PwdlockRecord = PwdlockRecord(
        id = o.getString("id").lowercase(),
        type = o.optString("type", "login"),
        title = o.optString("title", ""),
        username = o.optString("username", ""),
        password = o.optString("password", ""),
        url = o.optString("url", ""),
        category = o.optString("category", ""),
        note = o.optString("note", ""),
        createdAtMs = o.optLong("createdAtMs", 0),
        updatedAtMs = o.optLong("updatedAtMs", 0),
        revision = o.optLong("revision", 1),
        deviceId = o.optString("deviceId", ""),
    )
}
