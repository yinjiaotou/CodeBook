package com.pwdlock.android.data.vault

import com.pwdlock.android.data.model.LocalConflict
import com.pwdlock.android.data.model.PwdlockRecord
import org.json.JSONArray
import org.json.JSONObject

/**
 * 本地冲突列表的 JSON 编解码（org.json）。
 * 仅用于本地 `conflicts.enc` 持久化，格式为 Android 内部私有，不进入 `.pwdlock` 归档。
 */
object ConflictJson {
    fun encode(conflicts: List<LocalConflict>): String {
        val arr = JSONArray()
        conflicts.forEach { c ->
            arr.put(JSONObject().apply {
                put("id", c.id)
                put("recordId", c.recordId)
                put("title", c.title)
                put("createdAtMs", c.createdAtMs)
                put("local", recordToJson(c.local))
                put("imported", recordToJson(c.imported))
            })
        }
        return JSONObject().put("conflicts", arr).toString()
    }

    fun decode(json: String): List<LocalConflict> {
        val root = JSONObject(json)
        val arr = root.optJSONArray("conflicts") ?: return emptyList()
        val out = mutableListOf<LocalConflict>()
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            out.add(
                LocalConflict(
                    id = o.getString("id"),
                    recordId = o.getString("recordId"),
                    title = o.optString("title", ""),
                    createdAtMs = o.optLong("createdAtMs", 0),
                    local = jsonToRecord(o.getJSONObject("local")),
                    imported = jsonToRecord(o.getJSONObject("imported")),
                )
            )
        }
        return out
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
