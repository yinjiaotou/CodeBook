package com.pwdlock.android.data.vault

import android.content.Context
import android.util.Base64
import com.pwdlock.android.data.model.LocalConflict
import com.pwdlock.android.data.model.PwdlockRecord

/**
 * 本地模式存储后端（独立模块）。
 *
 * 职责单一且自包含：仅把内存中的 records / conflicts 加密落盘到本机 `VaultStore`，
 * 不涉及任何网络、账户或服务端概念。所有「在线」相关逻辑都在 [OnlineVaultBackend]，
 * 二者通过 [VaultBackend] 接口接入 [VaultSession]，互不依赖。
 */
class LocalVaultBackend(private val context: Context) : VaultBackend {
    override val isOnline: Boolean = false
    private val store = VaultStore(context)

    override suspend fun persistState(context: Context, records: List<PwdlockRecord>, conflicts: List<LocalConflict>) {
        val key = VaultSession.vaultKey ?: return
        store.writePayload(VaultCipher.encryptPayload(records, VaultSession.deviceId, key))
        store.writeConflicts(
            VaultCipher.encryptBytes(
                ConflictJson.encode(conflicts).toByteArray(Charsets.UTF_8),
                key,
            ),
        )
    }

    override suspend fun pushRecords(context: Context, records: List<PwdlockRecord>, op: String) {
        // 本地模式无云端，无需推送。
    }

    override suspend fun sync(context: Context): OnlineSyncResult {
        // 本地模式无远端，无需同步。
        return OnlineSyncResult.SUCCESS
    }

    override suspend fun flushPending(context: Context): OnlineSyncResult {
        // 本地模式无待传队列。
        return OnlineSyncResult.SUCCESS
    }

    override fun readEnvelope(context: Context): String? =
        if (store.exists()) Base64.encodeToString(store.readMeta(), Base64.NO_WRAP) else null

    override fun onMasterPasswordChanged(context: Context, envelopeB64: String) {
        store.writeMeta(Base64.decode(envelopeB64, Base64.NO_WRAP))
    }

    override fun logout(context: Context) {
        // 本地模式仅清内存（由 VaultSession.lock 处理），本机文件保留以便下次解锁。
    }
}
