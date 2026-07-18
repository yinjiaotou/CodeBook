package com.pwdlock.android.data.vault

import android.content.Context
import java.io.File

/**
 * 本地保险库的文件化存储（明文在内存，文件均在端侧加密）。
 *
 * - `vault_meta.bin`：112 字节 [com.pwdlock.android.crypto.VaultMetadata]（vaultKey 的加密信封）
 * - `vault_payload.enc`：记录负载，格式为 `nonce(12) || AES-GCM(ciphertext || tag(16))`，密钥为内存中的 vaultKey
 * - `device_id.txt`：本机 deviceId（小写 UUID）
 *
 * 未解锁前磁盘上只有 `vault_meta.bin`；vaultKey 绝不以明文落盘。
 */
class VaultStore(private val context: Context) {
    private val dir = File(context.filesDir, "pwdlock")
    private val metaFile = File(dir, "vault_meta.bin")
    private val payloadFile = File(dir, "vault_payload.enc")
    private val conflictsFile = File(dir, "conflicts.enc")
    private val deviceIdFile = File(dir, "device_id.txt")

    fun exists(): Boolean = metaFile.exists()
    fun readMeta(): ByteArray = metaFile.readBytes()
    fun writeMeta(bytes: ByteArray) { dir.mkdirs(); metaFile.writeBytes(bytes) }
    fun readPayload(): ByteArray = payloadFile.readBytes()
    fun writePayload(bytes: ByteArray) { dir.mkdirs(); payloadFile.writeBytes(bytes) }

    /** 冲突列表持久化（`nonce(12) || AES-GCM` 密文，密钥为内存中的 vaultKey）。 */
    fun hasConflicts(): Boolean = conflictsFile.exists()
    fun readConflicts(): ByteArray = conflictsFile.readBytes()
    fun writeConflicts(bytes: ByteArray) { dir.mkdirs(); conflictsFile.writeBytes(bytes) }

    fun readDeviceId(): String? =
        if (deviceIdFile.exists()) deviceIdFile.readText().trim().ifBlank { null } else null
    fun writeDeviceId(id: String) { dir.mkdirs(); deviceIdFile.writeText(id) }

    /** 取得导出文件落盘路径（如 <ts>.pwdlock）。 */
    fun exportFile(name: String): File {
        val d = File(dir, "export").also { it.mkdirs() }
        return File(d, name)
    }
}
