package com.pwdlock.android.data.vault

import com.pwdlock.android.crypto.AesGcm
import com.pwdlock.android.data.model.PwdlockPayload
import com.pwdlock.android.data.model.PwdlockRecord
import com.pwdlock.android.data.vault.VaultJson
import java.util.UUID
import kotlin.text.Charsets

/**
 * 本地/在线共用的负载加解密助手。
 *
 * 负载格式（records → `PwdlockPayload` → JSON → nonce||AES-GCM）在两种模式间完全一致，
 * 区别仅在于落盘目录（本地 `VaultStore` / 在线 `OnlineVaultCache`）。把这部分纯函数抽出来，
 * 既避免本地与在线各自重复实现，也让两个存储后端保持「独立但同构」。
 */
object VaultCipher {
    /** 由当前内存记录构造待持久化的 [PwdlockPayload]（不含 tombstone / conflictGroups）。 */
    fun buildPayload(records: List<PwdlockRecord>, deviceId: String?): PwdlockPayload {
        val dev = deviceId?.let { runCatching { UUID.fromString(it) }.getOrNull() } ?: UUID.randomUUID()
        return PwdlockPayload(
            exportId = UUID.randomUUID(),
            sourceVaultId = dev,
            createdAtMs = System.currentTimeMillis(),
            records = records,
        )
    }

    fun encryptPayload(records: List<PwdlockRecord>, deviceId: String?, key: ByteArray): ByteArray =
        encryptBytes(VaultJson.encodePayload(buildPayload(records, deviceId)).toByteArray(Charsets.UTF_8), key)

    fun decryptPayload(bytes: ByteArray, key: ByteArray): PwdlockPayload =
        VaultJson.decodePayload(String(decryptBytes(bytes, key), Charsets.UTF_8))

    fun encryptBytes(plaintext: ByteArray, key: ByteArray): ByteArray {
        val nonce = AesGcm.randomNonce()
        return nonce + AesGcm.seal(plaintext, key, nonce)
    }

    fun decryptBytes(bytes: ByteArray, key: ByteArray): ByteArray {
        val nonce = bytes.copyOfRange(0, 12)
        val sealed = bytes.copyOfRange(12, bytes.size)
        return AesGcm.open(sealed, key, nonce)
    }
}
