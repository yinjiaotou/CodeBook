package com.pwdlock.android.data.online

import android.content.Context
import com.pwdlock.android.crypto.AesGcm
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * 在线保险库的本地加密缓存（与本地模式同构，但按服务端 `vaultId` 隔离目录）。
 *
 * 目录：`files/pwdlock-online/<vaultId>/`
 * - `vault_meta.bin`：Vault Key 信封（与上传到服务端的 base64 同款）
 * - `vault_payload.enc`：记录负载，`nonce(12) || AES-GCM(ciphertext || tag(16))`，密钥为内存 vaultKey
 * - `conflicts.enc`：待裁决冲突（同上加密）
 *
 * 仅作离线可读缓存；真相在云端，解锁/同步时以服务端变更为准合并。
 */
class OnlineVaultCache(private val context: Context, private val vaultId: String) {
    private val dir = File(File(context.filesDir, "pwdlock-online"), vaultId)
    private val metaFile = File(dir, "vault_meta.bin")
    private val payloadFile = File(dir, "vault_payload.enc")
    private val conflictsFile = File(dir, "conflicts.enc")
    private val pendingFile = File(dir, "pending.json")

    fun exists(): Boolean = payloadFile.exists()
    fun readMeta(): ByteArray = metaFile.readBytes()
    fun writeMeta(bytes: ByteArray) { dir.mkdirs(); metaFile.writeBytes(bytes) }

    fun readPayload(): ByteArray = payloadFile.readBytes()
    fun writePayload(bytes: ByteArray) { dir.mkdirs(); payloadFile.writeBytes(bytes) }

    fun hasConflicts(): Boolean = conflictsFile.exists()
    fun readConflicts(): ByteArray = conflictsFile.readBytes()
    fun writeConflicts(bytes: ByteArray) { dir.mkdirs(); conflictsFile.writeBytes(bytes) }

    /** 用内存 vaultKey 加密明文（nonce || AES-GCM）。 */
    fun encrypt(plaintext: ByteArray, key: ByteArray): ByteArray {
        val nonce = AesGcm.randomNonce()
        return nonce + AesGcm.seal(plaintext, key, nonce)
    }

    /** 解密 `encrypt` 产物。 */
    fun decrypt(enc: ByteArray, key: ByteArray): ByteArray {
        val nonce = enc.copyOfRange(0, 12)
        val sealed = enc.copyOfRange(12, enc.size)
        return AesGcm.open(sealed, key, nonce)
    }

    // region 离线待传队列（pending.json）

    /** 读取待传队列。每条含已封印的密文信封（ciphertext/signature/changeId/deviceId），本机不留存明文变更。 */
    fun readPending(): List<PendingEntry> {
        if (!pendingFile.exists()) return emptyList()
        return try {
            val arr = JSONArray(pendingFile.readText())
            List(arr.length()) { i ->
                val o = arr.getJSONObject(i)
                PendingEntry(
                    op = o.getString("op"),
                    ciphertext = o.getString("ciphertext"),
                    signature = o.getString("signature"),
                    changeId = o.getString("changeId"),
                    deviceId = o.getString("deviceId"),
                )
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    /** 覆盖写入待传队列（仅密文信封，与发往服务端的内容一致）。 */
    fun writePending(list: List<PendingEntry>) {
        dir.mkdirs()
        val arr = JSONArray()
        list.forEach { e ->
            arr.put(
                JSONObject()
                    .put("op", e.op)
                    .put("ciphertext", e.ciphertext)
                    .put("signature", e.signature)
                    .put("changeId", e.changeId)
                    .put("deviceId", e.deviceId),
            )
        }
        pendingFile.writeText(arr.toString())
    }

    // endregion

    /** 清空整个在线缓存目录（登出时调用，重新登录会重建）。 */
    fun wipe() {
        dir.deleteRecursively()
    }
}

/** 离线待传队列中的一条变更：已封印的密文信封（本机不留存明文）。 */
data class PendingEntry(
    val op: String,
    val ciphertext: String,
    val signature: String,
    val changeId: String,
    val deviceId: String,
)
