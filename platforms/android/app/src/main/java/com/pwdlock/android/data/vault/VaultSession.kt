package com.pwdlock.android.data.vault

import android.content.Context
import android.util.Base64
import android.util.Log
import com.pwdlock.android.crypto.CryptoIO
import com.pwdlock.android.crypto.PwdlockArchive
import com.pwdlock.android.crypto.VaultBootstrap
import com.pwdlock.android.crypto.VaultKeyEnvelope
import com.pwdlock.android.crypto.VaultMetadataCodec
import com.pwdlock.android.data.model.LocalConflict
import com.pwdlock.android.data.model.PwdlockPayload
import com.pwdlock.android.data.model.PwdlockRecord
import com.pwdlock.android.data.model.toVaultItem
import com.pwdlock.android.data.model.VaultItem
import com.pwdlock.android.data.network.ApiClient
import com.pwdlock.android.data.vault.OnlineSyncResult
import com.pwdlock.android.data.network.ApiException
import com.pwdlock.android.data.online.OnlineAccountStore
import com.pwdlock.android.data.online.OnlineVaultBackend
import java.text.Normalizer
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * 会话门面（进程内单例）。
 *
 * 只负责「已解锁会话状态」的维护与向 UI 暴露观察流（[items] / [conflicts] / [unlocked]），
 * 以及作为本地 / 在线两种模式的统一入口。**不内含任何 onlineMode 业务分支**：
 * 记录的增删改、导入合并、冲突裁决、同步与补传，全部委托给当前激活的 [VaultBackend]。
 *
 * - 本地模式  → [LocalVaultBackend]（仅本机文件持久化）
 * - 在线模式  → [OnlineVaultBackend]（API 通信 + 本地加密缓存 + 离线补传队列 + 远端同步）
 *
 * 记录模型（[PwdlockRecord]）与密码学原语为两模式共用；「传输层」业务由两个独立后端各自完成，
 * 二者通过 [VaultBackend] 接口接入，互不依赖——本地与在线在代码结构上是清晰分离的两个模块。
 */
object VaultSession {
    private const val TAG = "VaultSession"
    private val _items = MutableStateFlow<List<VaultItem>>(emptyList())
    val items: StateFlow<List<VaultItem>> = _items.asStateFlow()

    private val _conflicts = MutableStateFlow<List<LocalConflict>>(emptyList())
    val conflicts: StateFlow<List<LocalConflict>> = _conflicts.asStateFlow()

    /** 解锁状态（供自动锁定 / 导航层观察）。 */
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
     * 导入流程进行中（停留在导入预览页）。为 true 时豁免自动锁定，确保「确认导入」时
     * 内存中的 vaultKey 一定在线，避免导入被锁定中断而丢失。
     */
    var importFlowActive: Boolean = false

    /** 待合并的导入负载（明文）。锁定时由解锁页自动执行合并，避免导入因锁定丢失。 */
    var pendingMergePayload: PwdlockPayload? = null

    /**
     * 是否为在线会话。**仅用于导航层决定锁定后的回落地**（在线回在线主密码页，本地回本地锁页）；
     * 业务代码（upsert / delete / 等）不得据此分支，统一委托 [backend]。
     */
    var onlineMode: Boolean = false
        private set

    /** 当前激活的存储后端；加锁时置空。 */
    private var backend: VaultBackend? = null

    /**
     * 会话级协程作用域。UI 面向的（非 suspend）业务方法（upsert / delete / 导入合并 / 冲突裁决 / 创建）
     * 把「落盘 + 上云」这类 suspend 调用统一丢到这个作用域里异步执行，避免阻塞 UI 线程；
     * 内存态的更新（emitState）仍是同步的，保证 UI 即时刷新。
     */
    private val sessionScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    // region 状态维护

    internal fun emitState() {
        // 数据卫生：若记录出现重复 id（例如历史同步异常或旧缓存损坏），去重后发射。
        // 保留第一次出现，避免 LazyColumn key 重复崩溃。
        val dedupedRecords = records.distinctBy { it.id }
        if (dedupedRecords.size != records.size) {
            Log.w(TAG, "records contained ${records.size - dedupedRecords.size} duplicate id(s); deduplicated before emitting")
            records = dedupedRecords
        }
        _items.value = dedupedRecords.map { it.toVaultItem() }
        _conflicts.value = conflictList
        _unlocked.value = vaultKey != null
    }

    internal fun snapshotRecords(): List<PwdlockRecord> = records
    internal fun snapshotConflicts(): List<LocalConflict> = conflictList

    fun isUnlocked(): Boolean = vaultKey != null
    fun hasVault(context: Context): Boolean = VaultStore(context).exists()

    fun setPendingImport(bytes: ByteArray) { pendingImportBytes = bytes }
    fun clearPendingImport() { pendingImportBytes = null }

    // endregion

    // region 本地模式生命周期

    /** 本地创建保险库。 */
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
        onlineMode = false
        backend = LocalVaultBackend(context)
        // 新建保险库会生成全新 vaultKey；清掉可能残留的旧指纹凭据，避免指纹封存的是旧 key 导致解锁失效。
        BiometricUnlock.disable(context)
        emitState()
        sessionScope.launch {
            backend?.persistState(context, records, conflictList)
        }
    }

    /** 本地主密码解锁。 */
    fun unlock(context: Context, masterPassword: String): Boolean = try {
        val store = VaultStore(context)
        val meta = VaultMetadataCodec.decode(store.readMeta())
        val key = VaultKeyEnvelope.unwrap(meta, masterPassword)
        loadUnlocked(context, key)
        true
    } catch (_: Exception) {
        false
    }

    /** 指纹解锁路径：用已解出的 vaultKey 直接解锁。 */
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
        records = VaultCipher.decryptPayload(store.readPayload(), key).records
        conflictList = if (store.hasConflicts()) {
            try {
                ConflictJson.decode(String(VaultCipher.decryptBytes(store.readConflicts(), key), Charsets.UTF_8))
            } catch (_: Exception) {
                emptyList()
            }
        } else {
            emptyList()
        }
        onlineMode = false
        backend = LocalVaultBackend(context)
        emitState()
    }

    /** 清空内存态（保留 onlineMode 以决定锁定回落地）；后端引用一并置空。 */
    fun lock() {
        vaultKey = null
        records = emptyList()
        conflictList = emptyList()
        deviceId = null
        importFlowActive = false
        backend = null
        emitState()
    }

    // endregion

    fun getRecord(id: String): PwdlockRecord? = records.firstOrNull { it.id == id }

    /** 新增或更新一条记录；返回记录 id。落地与（在线）上传统一委托给 [backend]。 */
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
                revision = 0,
                deviceId = deviceId ?: UUID.randomUUID().toString(),
            )
        }
        records = if (existing != null) {
            records.map { if (it.id == record.id) record else it }
        } else {
            records + record
        }
        emitState()
        sessionScope.launch {
            backend?.persistState(context, records, conflictList)
            backend?.pushRecords(context, listOf(record), "upsert")
        }
        return record.id
    }

    /** 删除一条记录。落地与（在线）上传统一委托给 [backend]。 */
    fun delete(context: Context, id: String) {
        val key = checkUnlocked()
        val removed = records.firstOrNull { it.id == id }
        records = records.filter { it.id != id }
        emitState()
        sessionScope.launch {
            backend?.persistState(context, records, conflictList)
            if (removed != null) backend?.pushRecords(context, listOf(removed), "delete")
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

    /** 干跑合并摘要（不改动数据），用于导入预览页展示真实数量。 */
    fun previewSummary(payload: PwdlockPayload, conflictFree: Boolean = false): MergeSummary {
        var added = 0
        var identical = 0
        var conflicts = 0
        for (imported in payload.records) {
            val local = records.firstOrNull { it.id == imported.id }
            when {
                local == null -> added++
                logicallyEquivalent(local, imported) -> identical++
                // 无冲突模式（在线导入）：同 id 异内容视为「覆盖」，不计入冲突。
                conflictFree -> added++
                else -> conflicts++
            }
        }
        return MergeSummary(added, identical, conflicts)
    }

    /**
     * 合并导入记录：
     * - 本地无同 id → 新增；
     * - 内容逻辑等价 → 跳过；
     * - 同 id 内容不同 → 本地模式进入待裁决冲突中心，在线模式直接覆盖（[conflictFree] = true）。
     *
     * 在线模式下，新增 / 覆盖的记录都会作为变更推送回云端（由 [backend] 处理）；
     * 因在线模式不存在「冲突」概念，[conflictFree] 由调用方（UI 层）按当前激活模式传入。
     */
    fun mergeImport(context: Context, payload: PwdlockPayload, conflictFree: Boolean = false): MergeSummary {
        val key = checkUnlocked()
        val now = System.currentTimeMillis()
        val mergedRecords = records.toMutableList()
        val mergedConflicts = conflictList.toMutableList()
        val addedRecords = mutableListOf<PwdlockRecord>()
        var added = 0
        var identical = 0
        var conflicts = 0

        for (imported in payload.records) {
            val idx = mergedRecords.indexOfFirst { it.id == imported.id }
            if (idx < 0) {
                mergedRecords.add(imported)
                addedRecords.add(imported)
                added++
                continue
            }
            val local = mergedRecords[idx]
            if (logicallyEquivalent(local, imported)) {
                identical++
                continue
            }
            if (conflictFree) {
                // 在线模式：直接覆盖本地版，不存在冲突中心。
                mergedRecords[idx] = imported
                addedRecords.add(imported)
                added++
                continue
            }
            // 去重：同一记录、同样的本地/导入内容已有待裁决冲突则跳过。
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
        emitState()
        sessionScope.launch {
            backend?.persistState(context, records, conflictList)
            backend?.pushRecords(context, addedRecords, "upsert")
        }
        return MergeSummary(added, identical, conflicts)
    }

    // endregion

    // region 冲突裁决（导入冲突 & 在线同步冲突共用同一模型，裁决结果由 backend 决定走向）

    /** 保留本地版：仅移除冲突，本地记录不变。在线模式下本地版会回传云端。 */
    fun resolveKeepLocal(context: Context, conflictId: String) {
        val key = checkUnlocked()
        val conflict = conflictList.firstOrNull { it.id == conflictId } ?: return
        conflictList = conflictList.filter { it.id != conflictId }
        emitState()
        sessionScope.launch {
            backend?.persistState(context, records, conflictList)
            backend?.pushRecords(context, listOf(conflict.local), "upsert")
        }
    }

    /** 用导入版替换本地记录，然后移除冲突。在线模式下该版本会回传云端。 */
    fun resolveUseImported(context: Context, conflictId: String) {
        val key = checkUnlocked()
        val conflict = conflictList.firstOrNull { it.id == conflictId } ?: return
        records = records.map { if (it.id == conflict.recordId) conflict.imported else it }
        conflictList = conflictList.filter { it.id != conflictId }
        emitState()
        sessionScope.launch {
            backend?.persistState(context, records, conflictList)
            backend?.pushRecords(context, listOf(conflict.imported), "upsert")
        }
    }

    // endregion

    // region 远端变更合并（由 OnlineVaultBackend.sync 回调，纯记录模型操作）

    /**
     * 应用远端 upsert：在线模式服务端即真理——直接用远端记录覆盖本地同 id 记录。
     * 同 id 不同内容也直接覆盖（last-write-wins，差异最终由待传队列回传云端收敛），
     * 绝不进入冲突中心：在线模式的密码库数据全部来自线上数据库，不存在「冲突」概念。
     *
     * 注意：本函数仅由 [com.pwdlock.android.data.online.OnlineVaultBackend] 的同步流程调用，
     * 本地模式走自己的合并语义，不存在此路径。
     */
    internal fun reconcileRemoteUpsert(record: PwdlockRecord) {
        val idx = records.indexOfFirst { it.id == record.id }
        records = if (idx < 0) {
            records + record
        } else {
            records.toMutableList().apply { this[idx] = record }
        }
    }

    internal fun reconcileRemoteDelete(recordId: String) {
        records = records.filter { it.id != recordId }
    }

    // endregion

    // region 在线模式入口（引导 + 建立后端；会话状态仍由门面持有）

    /**
     * 注册在线账户：注册账号 → 保存令牌 → 查询云端保险库列表。
     * 注册成功 ≠ 已有保险库：新账号必然无库，由后续「创建主密码」流程（[OnlineMasterPasswordScreen]
     * 的 createMode）真正建库。与 macOS 一致：注册只建立登录态，不创建保险库。
     */
    suspend fun registerOnline(
        context: Context,
        loginName: String,
        loginPassword: String,
    ) {
        val api = ApiClient(OnlineAccountStore.baseUrl(context))
        val token = api.register(loginName, loginPassword)
        OnlineAccountStore.saveCredentials(context, token, loginName)

        // 查询云端保险库，记录是否存在（供主密码页判定 createMode / unlockMode）。
        val vaults = try {
            api.listVaults(token)
        } catch (_: Exception) {
            emptyList()
        }
        if (vaults.isNotEmpty()) {
            val v = vaults[0]
            OnlineAccountStore.saveVault(context, v.id, v.encryptedKeyEnvelope)
        } else {
            // 无库：清空 vaultId，主密码页进入「创建主密码」流程。
            OnlineAccountStore.saveVault(context, "", "")
        }
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
     * 用主密码解锁在线保险库：解密 Vault Key →（若无设备则登记）→ 进入在线会话 →
     * 全量从云端拉取（游标归零）解密后显示。在线模式数据一律以服务端为真理，本机不缓存记录副本。
     * 若登录后服务端无保险库（vaultId 为空），则在此「创建」保险库（生成 vaultKey + 信封 + 登记设备）。
     */
    suspend fun unlockOnline(context: Context, masterPassword: String) = withContext(Dispatchers.IO) {
        val token = OnlineAccountStore.token(context) ?: throw IllegalStateException("未登录")
        val api = ApiClient(OnlineAccountStore.baseUrl(context))
        val vaultId = OnlineAccountStore.vaultId(context)

        val online: OnlineVaultBackend
        if (vaultId.isBlank()) {
            // 待创建分支：登录后服务端无保险库（即从未创建过主密码）。与 Mac 端一致：
            // 此处即以该主密码「创建」在线保险库，创建成功后进入主界面（空库）。
            val created = VaultBootstrap.create(masterPassword)
            vaultKey = created.vaultKey
            val envB64 = Base64.encodeToString(VaultMetadataCodec.encode(created.metadata), Base64.NO_WRAP)
            val vault = api.createVault(envB64, token)
            OnlineAccountStore.saveVault(context, vault.id, envB64)
            online = OnlineVaultBackend(context, vault.id, vaultKey!!)
            // 必须登记本机设备：否则 signingSeed 为空，此后「新增/修改记录」会因 pushRecords 提前返回而永远推不上云端。
            online.ensureDevice()
            records = emptyList()
            conflictList = emptyList()
        } else {
            val meta = VaultMetadataCodec.decode(Base64.decode(OnlineAccountStore.envelope(context), Base64.NO_WRAP))
            vaultKey = VaultKeyEnvelope.unwrap(meta, masterPassword)
            online = OnlineVaultBackend(context, vaultId, vaultKey!!)
            if (!OnlineAccountStore.hasDevice(context)) online.ensureDevice()
            // 在线模式数据一律以服务端为真理：进入即全量从云端拉取，不在本机缓存读取。
            records = emptyList()
            conflictList = emptyList()
        }

        onlineMode = true
        deviceId = OnlineAccountStore.deviceId(context).ifBlank { null }
        backend = online
        emitState()
        // 总是从游标 0 全量拉取：彻底规避历史坏游标导致空库，个人库数据量极小、幂等，成本可忽略。
        OnlineAccountStore.saveCursor(context, "0")
        // 解锁即进入 VaultHome：云端同步在后台进行。除「登录已过期（HTTP 401）」外，任何同步失败
        // （网络/验签/解密）都绝不让解锁闪退，仅记日志；之后用户可在密码库首页下拉刷新重试。
        // 登录已过期的，清会话态并抛 TokenExpired，由解锁页跳回登录页并提示。
        val syncResult = try {
            online.sync(context)
        } catch (t: Throwable) {
            Log.e(TAG, "post-unlock sync crashed (ignored to avoid crash)", t)
            OnlineSyncResult.TRANSPORT_ERROR
        }
        if (syncResult == OnlineSyncResult.AUTH_EXPIRED) {
            logoutOnline(context)
            throw ApiException.TokenExpired()
        }
    }

    /**
     * 指纹解锁在线保险库：vaultKey 已由 Keystore 经指纹认证解出，跳过主密码解 envelope。
     * 其余流程与 [unlockOnline] 的「已有保险库」分支一致：进在线会话 → 全量从云端拉取 → 后台同步。
     * 仅在已存在 vaultId 时可用（开启指纹前必然已用主密码成功解锁过一次）。
     */
    suspend fun unlockOnlineWithVaultKey(context: Context, key: ByteArray) = withContext(Dispatchers.IO) {
        val vaultId = OnlineAccountStore.vaultId(context)
        if (vaultId.isBlank()) throw IllegalStateException("无在线保险库，请用主密码解锁")

        vaultKey = key
        val online = OnlineVaultBackend(context, vaultId, key)
        if (!OnlineAccountStore.hasDevice(context)) online.ensureDevice()
        // 在线模式数据一律以服务端为真理：进入即全量从云端拉取，不在本机缓存读取。
        records = emptyList()
        conflictList = emptyList()

        onlineMode = true
        deviceId = OnlineAccountStore.deviceId(context).ifBlank { null }
        backend = online
        emitState()
        OnlineAccountStore.saveCursor(context, "0")
        val syncResult = try {
            online.sync(context)
        } catch (t: Throwable) {
            Log.e(TAG, "post-biometric-unlock sync crashed (ignored to avoid crash)", t)
            OnlineSyncResult.TRANSPORT_ERROR
        }
        if (syncResult == OnlineSyncResult.AUTH_EXPIRED) {
            logoutOnline(context)
            throw ApiException.TokenExpired()
        }
    }

    /** 触发一次同步（在线拉取 + 补传；本地为 no-op）。返回 [OnlineSyncResult]，便于 UI 感知登录过期。 */
    suspend fun sync(context: Context): OnlineSyncResult {
        return backend?.sync(context) ?: OnlineSyncResult.SUCCESS
    }

    /** 冲刷离线待传队列（在线）；本地为 no-op。返回 [OnlineSyncResult]。 */
    suspend fun flushPending(context: Context): OnlineSyncResult {
        return backend?.flushPending(context) ?: OnlineSyncResult.SUCCESS
    }

    /** 离线待传变更数（在线模式；本地恒为 0）。 */
    suspend fun pendingCount(context: Context): Int = backend?.pendingCount(context) ?: 0

    /** 登出：清账户态与内存密钥（本地缓存文件保留，重新登录会被覆盖/重建）。 */
    fun logoutOnline(context: Context) {
        backend?.logout(context)
        onlineMode = false
        lock()
    }

    // endregion

    /** 修改主密码：用旧密码解出 vaultKey，再用新密码重新包装（记录不变，vaultKey 不变）。 */
    fun changeMasterPassword(context: Context, oldPassword: String, newPassword: String) {
        val oldEnvelopeB64 = backend?.readEnvelope(context)
            ?: throw IllegalStateException("no active vault")
        val meta = VaultMetadataCodec.decode(Base64.decode(oldEnvelopeB64, Base64.NO_WRAP))
        val key = VaultKeyEnvelope.unwrap(meta, oldPassword)
        val newMeta = VaultKeyEnvelope.wrap(
            vaultKey = key,
            masterPassword = newPassword,
            vaultID = meta.vaultID,
            passwordSalt = CryptoIO.randomBytes(16),
            wrapNonce = CryptoIO.randomBytes(12),
        )
        val newEnvB64 = Base64.encodeToString(VaultMetadataCodec.encode(newMeta), Base64.NO_WRAP)
        backend?.onMasterPasswordChanged(context, newEnvB64)
        vaultKey = key
    }

    // region 内部

    private fun currentPayload(): PwdlockPayload = VaultCipher.buildPayload(records, deviceId)

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
