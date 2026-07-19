package com.pwdlock.android.data.vault

import android.content.Context
import com.pwdlock.android.data.model.LocalConflict
import com.pwdlock.android.data.model.PwdlockRecord

/**
 * 存储后端统一接口：本地模式与在线模式各自实现，由 [VaultSession] 作为门面持有并委托。
 *
 * 设计要点（满足「本地 / 在线为完全独立模块」）：
 * - [VaultSession] 只维护「已解锁会话状态」（records / conflicts / vaultKey / StateFlow），
 *   业务方法（upsert / delete / mergeImport / 冲突裁决 / sync）**不内含任何 onlineMode 分支**，
 *   一律委托给当前激活的 [VaultBackend]。
 * - 本地实现 [LocalVaultBackend] 只做本机文件持久化；在线实现 [OnlineVaultBackend] 负责
 *   API 通信、本地加密缓存、离线补传队列与远端同步——两者互不依赖、互不可见。
 */
interface VaultBackend {
    /** 是否为在线后端（仅供导航层决定锁定后的回落地，业务代码不得据此分支）。 */
    val isOnline: Boolean

    /** 持久化当前完整状态（records + conflicts）。本地写文件；在线写本地缓存。 */
    suspend fun persistState(context: Context, records: List<PwdlockRecord>, conflicts: List<LocalConflict>)

    /** 把若干记录作为变更推送（在线上传；本地为 no-op）。op 为 "upsert" 或 "delete"。 */
    suspend fun pushRecords(context: Context, records: List<PwdlockRecord>, op: String)

    /** 拉取远端变更（在线）；本地为 no-op。返回 [OnlineSyncResult]，便于调用方感知登录过期。 */
    suspend fun sync(context: Context): OnlineSyncResult

    /** 冲刷离线待传队列（在线）；本地为 no-op。返回 [OnlineSyncResult]。 */
    suspend fun flushPending(context: Context): OnlineSyncResult

    /** 待传队列长度（在线）；本地恒为 0。供 UI 显示「未同步」标记。 */
    suspend fun pendingCount(context: Context): Int = 0

    /** 读取当前 Vault Key 信封（base64）。本地读文件；在线读账户态。修改主密码时用于解包。 */
    fun readEnvelope(context: Context): String?

    /** 主密码变更后写入新信封。本地重写文件；在线更新本地账户态（服务端信封需专门接口）。 */
    fun onMasterPasswordChanged(context: Context, envelopeB64: String)

    /** 登出清理（在线清账户态 + 缓存；本地无额外清理）。 */
    fun logout(context: Context)
}
