package com.pwdlock.android.data.vault

import android.content.Context
import com.pwdlock.android.crypto.AesGcm
import com.pwdlock.android.crypto.CryptoIO
import com.pwdlock.android.crypto.PwdlockArchive
import com.pwdlock.android.crypto.VaultBootstrap
import com.pwdlock.android.crypto.VaultKeyEnvelope
import com.pwdlock.android.crypto.VaultMetadataCodec
import com.pwdlock.android.data.model.LocalConflict
import com.pwdlock.android.data.model.PwdlockPayload
import com.pwdlock.android.data.model.PwdlockRecord
import com.pwdlock.android.data.model.VaultItem
import com.pwdlock.android.data.model.toVaultItem
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import android.os.Build
import com.pwdlock.android.crypto.online.OnlineSyncCrypto
import com.pwdlock.android.crypto.online.OnlineSyncEnvelope
import com.pwdlock.android.crypto.online.fromBase64
import com.pwdlock.android.crypto.online.toBase64
import com.pwdlock.android.data.network.ApiClient
import com.pwdlock.android.data.network.ApiException
import com.pwdlock.android.data.network.OnlineSyncEnvelopeWire
import com.pwdlock.android.data.online.OnlineAccountStore
import com.pwdlock.android.data.online.OnlineChangeJson
import com.pwdlock.android.data.online.OnlineVaultCache
import com.pwdlock.android.data.online.OnlineVaultChange
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.nio.ByteBuffer
import java.security.MessageDigest
import java.text.Normalizer
import java.util.UUID

/**
 * 本地模式会话（进程内单例）。
 *
 * 持有内存中的 `vaultKey`、记录列表与待裁决冲突；通过文件化 [VaultStore] 持久化。
 * - 锁定时清空内存态，vaultKey 不留盘（仅 112 字节信封落盘）。
 * - UI 通过 [items] / [conflicts] / [unlocked]（[StateFlow]）观察变化并自动重组。
 */
object VaultSession {
    private val _items = MutableStateFlow<List<VaultItem>>(emptyList())
    val items: StateFlow<List<VaultItem>> = _items.asStateFlow()

    private val _conflicts = MutableStateFlow<List<LocalConflict>>(emptyList())
    val conflicts: StateFlow<List<LocalConflict>> = _conflicts.asStateFlow()

    /** 解锁状态（供自动锁定/导航层观察）。 */
    private val _unlocked = MutableStateFlow(false)
    val unlocked: StateFlow<Boolean> = _unlocked.asStateFlow()

    var vaultKey: ByteArray? = null
        private set
    var deviceId: String? = null
        private set

    private var records: List<PwdlockRecord> = emptyList()
    private var conflictList: List<LocalConflict> = emptyList()

    var pendingImportBytes: ByteArray? = null
        private set

    /**
     * 导入流程进行中（停留在导入预览页）。为 true 时豁免自动锁定（切后台 / 前台闲置），
     * 确保「确认导入」时内存中的 vaultKey 一定在线，避免导入被锁定中断而丢失。
     * 离开导入预览页或锁定时由会话层重置。
     */
    var importFlowActive: Boolean = false

    /**
     * 待续做的导入负载（明文记录）。当「确认导入」时 vault 已被锁定，先把明文 payload 暂存，
     * 解锁成功后由解锁页自动执行合并，避免导入流程因锁定而丢失。
     */
    var pendingMergePayload: PwdlockPayload? = null

    // region 在线模式

    /** 当前是否为在线保险库会话（跨锁定保留，决定解锁页走本地/在线）。 */
    var onlineMode: Boolean = false
    /** 服务端分配的本保险库 UUID（注意：非信封里的 16 字节 vaultID）。 */
    private var onlineVaultId: String? = null
    /** 由 vaultKey 派生的变更加密密钥。 */
    var changeKey: ByteArray? = null
        private set
    /** deviceId → 原始公钥(base64) 映射，用于验签拉取到的变更。 */
    private var devicePubKeyMap: Map<String, String>? = null

    private val onlineScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    // endregion

    fun isUnlocked(): Boolean = vaultKey != null
    fun hasVault(context: Context): Boolean = VaultStore(context).exists()

    fun setPendingImport(bytes: ByteArray) { pendingImportBytes = bytes }
    fun clearPendingImport() { pendingImportBytes = null }

    private fun emit() {
        _items.value = records.map { it.toVaultItem() }
        _conflicts.value = conflictList
        _unlocked.value = vaultKey != null
    }

    // region 生命周期

    fun create(context: Context, masterPassword: String) {
        val created = VaultBootstrap.create(masterPassword)
        val dev = UUID.randomUUID()
        val store = VaultStore(context)
        store.writeMeta(VaultMetadataCodec.encode(created.metadata))
        store.writeDeviceId(dev.toString())
        deviceId = dev.toString()
        vaultKey = created.vaultKey
        records = emptyList()
        conflictList = emptyList()
        store.writePayload(encryptPayload(emptyPayload(dev), created.vaultKey))
        emit()
    }

    fun unlock(context: Context, masterPassword: String): Boolean = try {
        val store = VaultStore(context)
        val meta = VaultMetadataCodec.decode(store.readMeta())
        val key = VaultKeyEnvelope.unwrap(meta, masterPassword)
        loadUnlocked(context, key)
        true
    } catch (_: Exception) {
        false
    }

    /**
     * 用已解出的 vaultKey 直接解锁（指纹解锁路径）。
     * vaultKey 由 Keystore 密钥在指纹认证后解出，无需主密码。
     */
    fun unlockWithVaultKey(context: Context, key: ByteArray): Boolean = try {
        loadUnlocked(context, key)
        true
    } catch (_: Exception) {
        false
    }

    private fun loadUnlocked(context: Context, key: ByteArray) {
        val store = VaultStore(context)
        val dev = store.readDeviceId() ?: UUID.randomUUID().toString().also { store.writeDeviceId(it) }
        deviceId = dev
        vaultKey = key
        records = decryptPayload(store.readPayload(), key).records
        conflictList = if (store.hasConflicts()) {
            try { ConflictJson.decode(String(decryptBytes(store.readConflicts(), key), Charsets.UTF_8)) }
            catch (_: Exception) { emptyList() }
        } else emptyList()
        emit()
    }

    fun lock() {
        vaultKey = null
        records = emptyList()
        conflictList = emptyList()
        deviceId = null
        importFlowActive = false
        // 在线态：保留 onlineMode（决定解锁页路由），清空内存密钥与同步上下文。
        onlineVaultId = null
        changeKey = null
        devicePubKeyMap = null
        emit()
    }

    // endregion

    fun getRecord(id: String): PwdlockRecord? = records.firstOrNull { it.id == id }

    /** 新增或更新一条记录；返回记录 id。 */
    fun upsert(context: Context, draft: VaultRecordDraft): String {
        val key = checkUnlocked()
        val now = System.currentTimeMillis()
        val existing = draft.id?.let { getRecord(it) }
        val record = if (existing != null) {
            existing.copy(
                title = norm(draft.title),
                username = norm(draft.username),
                password = norm(draft.password),
                url = norm(draft.url),
                category = norm(draft.category),
                note = norm(draft.note),
                updatedAtMs = now,
                revision = existing.revision + 1,
            )
        } else {
            PwdlockRecord(
                id = UUID.randomUUID().toString(),
                type = "login",
                title = norm(draft.title),
                username = norm(draft.username),
                password = norm(draft.password),
                url = norm(draft.url),
                category = norm(draft.category),
                note = norm(draft.note),
                createdAtMs = now,
                updatedAtMs = now,
                revision = 1,
                deviceId = deviceId ?: UUID.randomUUID().toString(),
            )
        }
        records = if (existing != null) {
            records.map { if (it.id == record.id) record else it }
        } else {
            records + record
        }
        persist(context, key)
        emit()
        if (onlineMode && onlineVaultId != null && vaultKey != null) pushChange(context, record, "upsert")
        return record.id
    }

    fun delete(context: Context, id: String) {
        val key = checkUnlocked()
        val removed = records.firstOrNull { it.id == id }
        records = records.filter { it.id != id }
        persist(context, key)
        emit()
        if (removed != null && onlineMode && onlineVaultId != null && vaultKey != null) {
            pushChange(context, removed, "delete")
        }
    }

    // region 归档导入 / 导出

    fun export(exportPassword: String): ByteArray {
        checkUnlocked()
        return PwdlockArchive.export(currentPayload(), exportPassword)
    }

    fun importPreview(password: String): PwdlockPayload {
        val bytes = pendingImportBytes ?: throw IllegalStateException("no import source")
        return PwdlockArchive.`import`(bytes, password)
    }

    /**
     * 干跑合并摘要（不改动数据），用于导入预览页展示真实数量。
     * 参考 macOS `mergeImportedItems`：相同 id 且内容不同 → 冲突（不覆盖）。
     */
    fun previewSummary(payload: PwdlockPayload): MergeSummary {
        var added = 0
        var identical = 0
        var conflicts = 0
        for (imported in payload.records) {
            val local = records.firstOrNull { it.id == imported.id }
            when {
                local == null -> added++
                logicallyEquivalent(local, imported) -> identical++
                else -> conflicts++
            }
        }
        return MergeSummary(added, identical, conflicts)
    }

    /**
     * 合并导入记录（参考 macOS）：
     * - 本地无同 id → 新增
     * - 内容逻辑等价 → 跳过
     * - 同 id 内容不同 → 生成待裁决冲突（不静默覆盖），去重相同冲突
     */
    fun mergeImport(context: Context, payload: PwdlockPayload): MergeSummary {
        val key = checkUnlocked()
        val now = System.currentTimeMillis()
        val mergedRecords = records.toMutableList()
        val mergedConflicts = conflictList.toMutableList()
        var added = 0
        var identical = 0
        var conflicts = 0

        for (imported in payload.records) {
            val idx = mergedRecords.indexOfFirst { it.id == imported.id }
            if (idx < 0) {
                mergedRecords.add(imported)
                added++
                continue
            }
            val local = mergedRecords[idx]
            if (logicallyEquivalent(local, imported)) {
                identical++
                continue
            }
            // 去重：同一记录、同样的本地/导入内容已有待裁决冲突则跳过
            val duplicate = mergedConflicts.any {
                it.recordId == imported.id &&
                    logicallyEquivalent(it.local, local) &&
                    logicallyEquivalent(it.imported, imported)
            }
            if (duplicate) continue
            mergedConflicts.add(
                LocalConflict(
                    id = UUID.randomUUID().toString(),
                    recordId = imported.id,
                    title = local.title,
                    createdAtMs = now,
                    local = local,
                    imported = imported,
                )
            )
            conflicts++
        }

        records = mergedRecords
        conflictList = mergedConflicts
        persist(context, key)
        emit()
        return MergeSummary(added, identical, conflicts)
    }

    // endregion

    // region 冲突裁决（参考 macOS resolveKeepingLocal / resolveUsingImported）

    /** 保留本地版：直接删除该冲突，本地记录不变。 */
    fun resolveKeepLocal(context: Context, conflictId: String) {
        val key = checkUnlocked()
        conflictList = conflictList.filter { it.id != conflictId }
        persist(context, key)
        emit()
    }

    /** 用导入版替换本地记录，然后删除该冲突。 */
    fun resolveUseImported(context: Context, conflictId: String) {
        val key = checkUnlocked()
        val conflict = conflictList.firstOrNull { it.id == conflictId } ?: return
        records = records.map { if (it.id == conflict.recordId) conflict.imported else it }
        conflictList = conflictList.filter { it.id != conflictId }
        persist(context, key)
        emit()
    }

    // endregion

    // region 在线模式：注册 / 登录 / 解锁 / 同步 / 推送

    /**
     * 注册在线账户并创建云端保险库：
     * 注册账号 → 生成 Vault Key（主密码）→ 上传信封 → 登记本设备 Ed25519 密钥 → 初始化本地缓存。
     * 完成后直接进入空保险库。
     */
    suspend fun registerOnline(
        context: Context,
        loginName: String,
        loginPassword: String,
        masterPassword: String,
    ) {
        val api = ApiClient(OnlineAccountStore.baseUrl(context))
        val token = api.register(loginName, loginPassword)
        OnlineAccountStore.saveCredentials(context, token, loginName)

        val created = VaultBootstrap.create(masterPassword)
        vaultKey = created.vaultKey
        val envB64 = VaultMetadataCodec.encode(created.metadata).toBase64()
        val vault = api.createVault(envB64, token)
        OnlineAccountStore.saveVault(context, vault.id, envB64)
        enrollDevice(context, api, token)

        onlineVaultId = vault.id
        records = emptyList()
        conflictList = emptyList()
        val cache = OnlineVaultCache(context, vault.id)
        cache.writePayload(
            cache.encrypt(VaultJson.encodePayload(emptyPayload(UUID.randomUUID())).toByteArray(Charsets.UTF_8), vaultKey!!),
        )
        changeKey = OnlineSyncCrypto.deriveChangeKey(vaultKey!!)
        onlineMode = true
        emit()
    }

    /**
     * 登录在线账户：拿到令牌，列出保险库。
     * @return true 表示已有保险库（需主密码解密）；false 表示待创建（主密码步执行创建分支）。
     */
    suspend fun loginOnline(context: Context, loginName: String, loginPassword: String): Boolean {
        val api = ApiClient(OnlineAccountStore.baseUrl(context))
        val token = api.login(loginName, loginPassword)
        OnlineAccountStore.saveCredentials(context, token, loginName)
        val vaults = api.listVaults(token)
        return if (vaults.isEmpty()) {
            OnlineAccountStore.saveVault(context, "", "")
            false
        } else {
            val v = vaults[0]
            OnlineAccountStore.saveVault(context, v.id, v.encryptedKeyEnvelope)
            true
        }
    }

    /**
     * 用主密码解锁在线保险库：解密 Vault Key →（若无设备则登记）→ 载入本地缓存 → 同步云端变更。
     * 若登录后服务端无保险库（pendingCreate），则在此创建。
     */
    suspend fun unlockOnline(context: Context, masterPassword: String) {
        val token = OnlineAccountStore.token(context) ?: throw IllegalStateException("未登录")
        val api = ApiClient(OnlineAccountStore.baseUrl(context))
        val vaultId = OnlineAccountStore.vaultId(context)

        if (vaultId.isBlank()) {
            // 待创建分支：本端首次使用且服务端无保险库。
            val created = VaultBootstrap.create(masterPassword)
            vaultKey = created.vaultKey
            val envB64 = VaultMetadataCodec.encode(created.metadata).toBase64()
            val vault = api.createVault(envB64, token)
            OnlineAccountStore.saveVault(context, vault.id, envB64)
            enrollDevice(context, api, token)
            onlineVaultId = vault.id
            records = emptyList()
            conflictList = emptyList()
        } else {
            val meta = VaultMetadataCodec.decode(OnlineAccountStore.envelope(context).fromBase64())
            vaultKey = VaultKeyEnvelope.unwrap(meta, masterPassword)
            onlineVaultId = vaultId
            if (!OnlineAccountStore.hasDevice(context)) enrollDevice(context, api, token)
            val cache = OnlineVaultCache(context, vaultId)
            records = if (cache.exists()) {
                decryptPayload(cache.readPayload(), vaultKey!!).records
            } else {
                emptyList()
            }
            conflictList = if (cache.hasConflicts()) {
                try {
                    ConflictJson.decode(String(cache.decrypt(cache.readConflicts(), vaultKey!!), Charsets.UTF_8))
                } catch (_: Exception) {
                    emptyList()
                }
            } else {
                emptyList()
            }
        }
        deviceId = OnlineAccountStore.deviceId(context).ifBlank { null }
        changeKey = OnlineSyncCrypto.deriveChangeKey(vaultKey!!)
        onlineMode = true
        emit()
        syncOnline(context)
    }

    /** 从云端拉取变更：验签 → 解密 → 合并（冲突进冲突中心）→ 更新游标与本地缓存。 */
    suspend fun syncOnline(context: Context) {
        val token = OnlineAccountStore.token(context) ?: return
        val vaultId = onlineVaultId ?: return
        val key = vaultKey ?: return
        val api = ApiClient(OnlineAccountStore.baseUrl(context))

        try {
            val devices = api.listDevices(token)
            devicePubKeyMap = devices.associate { it.id to it.publicSigningKey }
        } catch (e: ApiException.TokenExpired) {
            logoutOnline(context)
            return
        } catch (e: Exception) {
            android.util.Log.w("OnlineSync", "listDevices failed", e)
        }

        val changes = try {
            api.listChanges(vaultId, OnlineAccountStore.cursor(context), token)
        } catch (e: ApiException.TokenExpired) {
            logoutOnline(context)
            return
        } catch (e: Exception) {
            android.util.Log.w("OnlineSync", "listChanges failed", e)
            return
        }

        var maxSeq = OnlineAccountStore.cursor(context).toLongOrNull() ?: 0L
        for (c in changes) {
            val pub = devicePubKeyMap?.get(c.deviceId)?.fromBase64()
            if (pub == null) {
                android.util.Log.w("OnlineSync", "no public key for device ${c.deviceId}; skip")
                continue
            }
            try {
                val plaintext = OnlineSyncCrypto.open(
                    OnlineSyncEnvelope(c.ciphertext, c.signature, c.changeId),
                    vaultId,
                    key,
                    pub,
                )
                val change = OnlineChangeJson.decode(plaintext)
                if (change.operation == "delete") applyRemoteDelete(change.record.id)
                else applyRemoteUpsert(change.record)
            } catch (e: Exception) {
                android.util.Log.w("OnlineSync", "verify/open change ${c.changeId} failed", e)
                continue
            }
            val seq = c.sequence.toLongOrNull() ?: 0L
            if (seq > maxSeq) maxSeq = seq
        }

        if (changes.isNotEmpty()) {
            OnlineAccountStore.saveCursor(context, maxSeq.toString())
            persist(context, key)
            emit()
        }
        OnlineAccountStore.saveLastSync(context, System.currentTimeMillis())
    }

    /** 登出：清除账户态与内存密钥（本地缓存文件保留，重新登录会被覆盖）。 */
    fun logoutOnline(context: Context) {
        OnlineAccountStore.clear(context)
        onlineMode = false
        onlineVaultId = null
        changeKey = null
        devicePubKeyMap = null
        lock()
    }

    /**
     * 登记本设备：生成 Ed25519 密钥对，上传公钥，私钥安全存储。
     * 服务端不存储私钥；私钥仅用于签署本设备上传的变更。
     */
    private suspend fun enrollDevice(context: Context, api: ApiClient, token: String) {
        val (seed, pub) = OnlineSyncCrypto.generateDeviceKey()
        val device = api.registerDevice(Build.MODEL ?: "Android device", pub.toBase64(), token)
        OnlineAccountStore.saveDevice(context, device.id, seed.toBase64())
    }

    /**
     * 推送一条变更（fire-and-forget，不阻塞本地写入）。
     * changeId 由 (vaultId, itemId, revision, op) 确定性派生，配合确定性 nonce 保证重试幂等。
     */
    private fun pushChange(context: Context, record: PwdlockRecord, op: String) {
        val vaultId = onlineVaultId ?: return
        val key = vaultKey ?: return
        val seedB64 = OnlineAccountStore.signingSeed(context)
        if (seedB64.isBlank()) return
        val changeId = deterministicChangeId(vaultId, record.id, record.revision, op)
        onlineScope.launch {
            try {
                val token = OnlineAccountStore.token(context) ?: return@launch
                val api = ApiClient(OnlineAccountStore.baseUrl(context))
                val plaintext = OnlineChangeJson.encode(OnlineVaultChange(op, record))
                val env = OnlineSyncCrypto.seal(plaintext, vaultId, changeId, key, seedB64.fromBase64())
                api.appendChange(
                    vaultId,
                    env.changeId,
                    OnlineAccountStore.deviceId(context),
                    OnlineSyncEnvelopeWire(env.ciphertext, env.signature),
                    token,
                )
            } catch (e: ApiException.TokenExpired) {
                android.util.Log.w("OnlineSync", "token expired; needs re-login")
            } catch (e: Exception) {
                android.util.Log.w("OnlineSync", "push $op failed", e)
            }
        }
    }

    private fun deterministicChangeId(vaultId: String, itemId: String, revision: Long, op: String): String {
        val raw = "$vaultId:$itemId:$revision:$op".toByteArray(Charsets.UTF_8)
        val hash = MessageDigest.getInstance("SHA-256").digest(raw)
        val msb = ByteBuffer.wrap(hash.copyOfRange(0, 8)).long
        val lsb = ByteBuffer.wrap(hash.copyOfRange(8, 16)).long
        return UUID(msb, lsb).toString()
    }

    /** 应用远端 upsert：同 id 同内容跳过；不同则进入冲突中心（忽略 deviceId 差异）。 */
    private fun applyRemoteUpsert(record: PwdlockRecord) {
        val idx = records.indexOfFirst { it.id == record.id }
        if (idx < 0) {
            records = records + record
            return
        }
        val local = records[idx]
        if (sameContent(local, record)) return
        val duplicate = conflictList.any {
            it.recordId == record.id && sameContent(it.local, local) && sameContent(it.imported, record)
        }
        if (duplicate) return
        conflictList = conflictList + LocalConflict(
            id = UUID.randomUUID().toString(),
            recordId = record.id,
            title = local.title,
            createdAtMs = System.currentTimeMillis(),
            local = local,
            imported = record,
        )
    }

    private fun applyRemoteDelete(recordId: String) {
        records = records.filter { it.id != recordId }
    }

    /** 内容等价（忽略 deviceId，仅比较业务字段与修订号）。 */
    private fun sameContent(a: PwdlockRecord, b: PwdlockRecord): Boolean =
        a.id == b.id &&
            a.title == b.title &&
            a.username == b.username &&
            a.password == b.password &&
            a.url == b.url &&
            a.category == b.category &&
            a.note == b.note &&
            a.createdAtMs == b.createdAtMs &&
            a.updatedAtMs == b.updatedAtMs &&
            a.revision == b.revision

    // endregion

    /** 修改主密码：用旧密码解出 vaultKey，再用新密码重新包装（记录不变，vaultKey 不变）。 */
    fun changeMasterPassword(context: Context, oldPassword: String, newPassword: String) {
        val store = VaultStore(context)
        val meta = VaultMetadataCodec.decode(store.readMeta())
        val key = VaultKeyEnvelope.unwrap(meta, oldPassword)
        val newMeta = VaultKeyEnvelope.wrap(
            vaultKey = key,
            masterPassword = newPassword,
            vaultID = meta.vaultID,
            passwordSalt = CryptoIO.randomBytes(16),
            wrapNonce = CryptoIO.randomBytes(12),
        )
        store.writeMeta(VaultMetadataCodec.encode(newMeta))
        vaultKey = key
    }

    // region 内部

    private fun persist(context: Context, key: ByteArray) {
        if (onlineVaultId != null) {
            // 在线模式：写入按 vaultId 隔离的本地缓存目录。
            val cache = OnlineVaultCache(context, onlineVaultId!!)
            cache.writePayload(cache.encrypt(VaultJson.encodePayload(currentPayload()).toByteArray(Charsets.UTF_8), key))
            cache.writeConflicts(cache.encrypt(ConflictJson.encode(conflictList).toByteArray(Charsets.UTF_8), key))
            return
        }
        val store = VaultStore(context)
        store.writePayload(encryptPayload(currentPayload(), key))
        store.writeConflicts(encryptBytes(ConflictJson.encode(conflictList).toByteArray(Charsets.UTF_8), key))
    }

    private fun currentPayload(): PwdlockPayload {
        val dev = deviceId?.let { UUID.fromString(it) } ?: UUID.randomUUID()
        return PwdlockPayload(
            exportId = UUID.randomUUID(),
            sourceVaultId = dev,
            createdAtMs = System.currentTimeMillis(),
            records = records,
        )
    }

    private fun emptyPayload(dev: UUID) = PwdlockPayload(
        exportId = UUID.randomUUID(),
        sourceVaultId = dev,
        createdAtMs = System.currentTimeMillis(),
        records = emptyList(),
    )

    private fun encryptPayload(p: PwdlockPayload, key: ByteArray): ByteArray =
        encryptBytes(VaultJson.encodePayload(p).toByteArray(Charsets.UTF_8), key)

    private fun decryptPayload(bytes: ByteArray, key: ByteArray): PwdlockPayload =
        VaultJson.decodePayload(String(decryptBytes(bytes, key), Charsets.UTF_8))

    private fun encryptBytes(plaintext: ByteArray, key: ByteArray): ByteArray {
        val nonce = AesGcm.randomNonce()
        return nonce + AesGcm.seal(plaintext, key, nonce)
    }

    private fun decryptBytes(bytes: ByteArray, key: ByteArray): ByteArray {
        val nonce = bytes.copyOfRange(0, 12)
        val sealed = bytes.copyOfRange(12, bytes.size)
        return AesGcm.open(sealed, key, nonce)
    }

    /** 逐字段比较是否逻辑等价（对齐 macOS `logicallyEquivalent`）。 */
    private fun logicallyEquivalent(a: PwdlockRecord, b: PwdlockRecord): Boolean =
        a.id == b.id &&
            a.title == b.title &&
            a.username == b.username &&
            a.password == b.password &&
            a.url == b.url &&
            a.category == b.category &&
            a.note == b.note &&
            a.createdAtMs == b.createdAtMs &&
            a.updatedAtMs == b.updatedAtMs &&
            a.revision == b.revision &&
            a.deviceId == b.deviceId

    private fun checkUnlocked(): ByteArray = vaultKey ?: throw IllegalStateException("vault is locked")
    private fun norm(s: String): String = Normalizer.normalize(s, Normalizer.Form.NFC)

    // endregion
}

/** 编辑页提交的草稿（id 为空表示新增）。 */
data class VaultRecordDraft(
    val id: String? = null,
    val title: String,
    val username: String,
    val password: String,
    val url: String,
    val category: String,
    val note: String,
)

/** 导入合并摘要（对齐 macOS `ImportMergeSummary`）。 */
data class MergeSummary(
    val added: Int,
    val identical: Int,
    val conflicts: Int,
)
