package com.pwdlock.android.data.online

import android.content.Context
import android.os.Build
import android.util.Log
import com.pwdlock.android.crypto.online.OnlineSyncCrypto
import com.pwdlock.android.crypto.online.OnlineSyncEnvelope
import com.pwdlock.android.crypto.online.fromBase64
import com.pwdlock.android.crypto.online.toBase64
import com.pwdlock.android.data.model.LocalConflict
import com.pwdlock.android.data.model.PwdlockRecord
import com.pwdlock.android.data.network.ApiClient
import com.pwdlock.android.data.network.ApiException
import com.pwdlock.android.data.network.OnlineSyncEnvelopeWire
import com.pwdlock.android.data.online.OnlineChangeJson
import com.pwdlock.android.data.vault.OnlineSyncResult
import com.pwdlock.android.data.vault.VaultBackend
import com.pwdlock.android.data.vault.VaultSession
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import java.util.UUID

/**
 * 在线模式存储后端（独立模块）。
 *
 * 负责在线模式全部「传输层」业务，与本地模式 [com.pwdlock.android.data.vault.LocalVaultBackend]
 * 通过统一接口 [VaultBackend] 接入 [VaultSession]，二者互不依赖：
 * - 与服务端 API 通信（registerDevice / listDevices / listChanges / appendChange）
 * - 本地加密缓存（[OnlineVaultCache]）的读写
 * - 离线 / 失败变更的**持久化待传队列**与补传（消除「fire-and-forget 失败即丢数据」）
 * - 解锁后 / 切回前台的远端变更拉取、验签、合并与冲突裁决回传
 *
 * 端到端加密保证：服务端只存密文与签名，所有加解密、验签均在客户端完成。
 */
class OnlineVaultBackend(
    private val context: Context,
    private val vaultId: String,
    private val vaultKey: ByteArray,
) : VaultBackend {
    override val isOnline: Boolean = true

    private val api = ApiClient(OnlineAccountStore.baseUrl(context))
    private val onlineScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var devicePubKeyMap: Map<String, String>? = null

    // region 持久化（在线模式不缓存明文/密文记录副本）

    /**
     * 在线模式数据一律以服务端为真理，不在本机保存可解读的保险库数据副本。
     * 仅「离线待传队列」会以密文形式暂存已封印的变更信封（与发往服务端的内容一致），
     * 由 [pushRecords]/[flushPending] 管理，不在此落盘记录列表。
     */
    override suspend fun persistState(context: Context, records: List<PwdlockRecord>, conflicts: List<LocalConflict>) {
        // 故意为空：在线模式无本地记录副本。
    }

    // endregion

    // region 上传（含离线补传队列）

    override suspend fun pushRecords(context: Context, records: List<PwdlockRecord>, op: String) {
        if (records.isEmpty()) return
        val seedB64 = OnlineAccountStore.signingSeed(context)
        if (seedB64.isBlank()) return
        val seed = seedB64.fromBase64()
        val deviceId = OnlineAccountStore.deviceId(context)
        if (deviceId.isBlank()) return
        // 落盘前即密封：本地待传队列仅保存密文信封（ciphertext/signature/changeId/deviceId），
        // 与发往服务端的内容完全一致，不在本机留存明文变更。
        // changeId 为随机 UUID（与 macOS 每条变更独立随机一致），保存于待传项以便重试时复用（服务端按 changeId 幂等）。
        val pending = readPending().toMutableList()
        for (r in records) {
            val change = OnlineVaultChange(op, r)
            val changeBytes = OnlineChangeJson.encode(change)
            val changeId = UUID.randomUUID().toString()
            val env = OnlineSyncCrypto.seal(changeBytes, vaultId, changeId, vaultKey, seed)
            pending.add(PendingEntry(op, env.ciphertext, env.signature, changeId, deviceId))
        }
        writePending(pending)
        flushPending(context)
    }

    override suspend fun flushPending(context: Context): OnlineSyncResult {
        val token = OnlineAccountStore.token(context) ?: return OnlineSyncResult.AUTH_EXPIRED
        val pending = readPending().toMutableList()
        if (pending.isEmpty()) return OnlineSyncResult.SUCCESS

        val remaining = mutableListOf<PendingEntry>()
        for (entry in pending) {
            try {
                api.appendChange(
                    vaultId,
                    entry.changeId,
                    entry.deviceId,
                    OnlineSyncEnvelopeWire(entry.ciphertext, entry.signature),
                    token,
                )
            } catch (e: ApiException.TokenExpired) {
                // 令牌失效：清空账户态并交还登录页（由调用方导航）。
                logout(context)
                return OnlineSyncResult.AUTH_EXPIRED
            } catch (e: Exception) {
                // 其他失败（网络抖动 / 服务端 5xx）保留队列，待下次冲刷。
                Log.w(TAG, "flush pending change failed", e)
                remaining.add(entry)
            }
        }
        writePending(remaining)
        return if (remaining.isEmpty()) OnlineSyncResult.SUCCESS else OnlineSyncResult.TRANSPORT_ERROR
    }

    override suspend fun pendingCount(context: Context): Int = readPending().size

    // endregion

    // region 拉取 / 合并（远端同步）

    override suspend fun sync(context: Context): OnlineSyncResult {
        val token = OnlineAccountStore.token(context) ?: return OnlineSyncResult.AUTH_EXPIRED

        // 1) 拉取设备公钥，用于验签远端变更。失败则放弃本次同步、保留游标（不前进），下次重试。
        val devices = try {
            api.listDevices(token)
        } catch (e: ApiException.TokenExpired) {
            logout(context)
            return OnlineSyncResult.AUTH_EXPIRED
        } catch (e: Exception) {
            Log.e(TAG, "listDevices failed; abort sync, keep cursor", e)
            return OnlineSyncResult.TRANSPORT_ERROR
        }
        devicePubKeyMap = devices.associate { it.id to it.publicSigningKey }

        // 2) 拉取自游标之后的全部变更。
        val changes = try {
            api.listChanges(vaultId, OnlineAccountStore.cursor(context), token)
        } catch (e: ApiException.TokenExpired) {
            logout(context)
            return OnlineSyncResult.AUTH_EXPIRED
        } catch (e: Exception) {
            Log.e(TAG, "listChanges failed; abort sync, keep cursor", e)
            return OnlineSyncResult.TRANSPORT_ERROR
        }

        // 3) 逐条验签 → 解密 → 合并（冲突进冲突中心）。
        //    只有「成功应用」的变更才推进游标；验签/解密/解码失败的变更保持原游标，留待下次重试，
        //    绝不允许「收到却没合并」就把游标推过它们，否则会被服务端按 after 永久过滤（数据丢失）。
        var maxAppliedSeq = OnlineAccountStore.cursor(context).toLongOrNull() ?: 0L
        var appliedAny = false
        for (c in changes) {
            val pub = devicePubKeyMap?.get(c.deviceId)?.fromBase64()
            if (pub == null) {
                Log.w(TAG, "no public key for device ${c.deviceId}; skip (keep cursor)")
                continue
            }
            val plaintext = try {
                OnlineSyncCrypto.open(
                    OnlineSyncEnvelope(c.ciphertext, c.signature, c.changeId),
                    vaultId,
                    vaultKey,
                    pub,
                )
            } catch (e: Exception) {
                Log.w(TAG, "verify/open change ${c.changeId} failed; skip (keep cursor)", e)
                continue
            }
            val change = try {
                OnlineChangeJson.decode(plaintext)
            } catch (e: Exception) {
                Log.w(TAG, "decode change ${c.changeId} failed; skip (keep cursor)", e)
                continue
            }
            if (change.operation == "delete") VaultSession.reconcileRemoteDelete(change.record.id)
            else VaultSession.reconcileRemoteUpsert(change.record)
            appliedAny = true
            val seq = c.sequence.toLongOrNull() ?: 0L
            if (seq > maxAppliedSeq) maxAppliedSeq = seq
        }

        // 4) 仅当确有成功应用的变更时推进游标 + 落盘；其它情况保留原游标，避免数据丢失。
        //    落盘失败（如 IO 异常）绝不让同步中断或崩溃，仅记日志，下次同步重试。
        if (appliedAny) {
            OnlineAccountStore.saveCursor(context, maxAppliedSeq.toString())
            try {
                persistState(context, VaultSession.snapshotRecords(), VaultSession.snapshotConflicts())
            } catch (e: Exception) {
                Log.e(TAG, "persistState after sync failed (ignored)", e)
            }
        }
        VaultSession.emitState()
        OnlineAccountStore.saveLastSync(context, System.currentTimeMillis())

        // 5) 拉取完成后，把本地离线期间的待传变更补传到云端。
        val flushResult = runCatching { flushPending(context) }
            .getOrElse { OnlineSyncResult.TRANSPORT_ERROR }
        // 补传若发现令牌失效，优先以 AUTH_EXPIRED 上报，使上层跳回登录页。
        return if (flushResult == OnlineSyncResult.AUTH_EXPIRED) flushResult else OnlineSyncResult.SUCCESS
    }

    // endregion

    // region 设备登记 / 信封 / 登出

    /** 登记本设备（仅首次）：生成 Ed25519 密钥对、上传公钥，私钥安全存储（服务端不存）。 */
    suspend fun ensureDevice() {
        if (OnlineAccountStore.hasDevice(context)) return
        val token = OnlineAccountStore.token(context) ?: return
        val (seed, pub) = OnlineSyncCrypto.generateDeviceKey()
        val device = api.registerDevice(Build.MODEL ?: "Android device", pub.toBase64(), token)
        OnlineAccountStore.saveDevice(context, device.id, seed.toBase64())
    }

    override fun readEnvelope(context: Context): String? =
        OnlineAccountStore.envelope(context).ifBlank { null }

    override fun onMasterPasswordChanged(context: Context, envelopeB64: String) {
        // 服务端信封需经专门接口更新（当前 serve 未提供），此处仅更新本地账户态，
        // 保证本机解锁一致；其他端需重新登录以拉取新信封。
        OnlineAccountStore.saveVault(context, OnlineAccountStore.vaultId(context), envelopeB64)
    }

    override fun logout(context: Context) {
        OnlineAccountStore.clear(context)
        // 清理本机在线缓存目录（重新登录会重建）。
        try {
            OnlineVaultCache(context, vaultId).wipe()
        } catch (_: Exception) {
        }
    }

    // endregion

    private fun readPending(): List<PendingEntry> = OnlineVaultCache(context, vaultId).readPending()
    private fun writePending(list: List<PendingEntry>) = OnlineVaultCache(context, vaultId).writePending(list)

    companion object {
        private const val TAG = "OnlineVaultBackend"
    }
}
