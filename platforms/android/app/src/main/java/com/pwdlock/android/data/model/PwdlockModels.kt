package com.pwdlock.android.data.model

import java.util.UUID

/**
 * 对齐 macOS `PwdlockCore` 的 `PwdlockRecord` / `PwdlockPayload` / `PwdlockTombstone` /
 * `PwdlockConflictGroup`。本地存储与 `.pwdlock` 归档共用的数据模型。
 *
 * 字段命名、UUID 小写、NFC 归一化等约束与 macOS 严格校验一致，保证跨端可互相导入导出。
 */
data class PwdlockRecord(
    val id: String,        // 小写 UUID
    val type: String = "login",
    val title: String,
    val username: String,
    val password: String,
    val url: String,
    val category: String,
    val note: String,
    val createdAtMs: Long,
    val updatedAtMs: Long,
    val revision: Long,
    val deviceId: String,  // 小写 UUID
)

data class PwdlockPayload(
    val schemaVersion: Int = 1,
    val exportId: UUID,
    val sourceVaultId: UUID,
    val createdAtMs: Long,
    val records: List<PwdlockRecord>,
    val tombstones: List<PwdlockTombstone> = emptyList(),
    val conflictGroups: List<PwdlockConflictGroup> = emptyList(),
)

data class PwdlockTombstone(
    val recordId: String,
    val deletedAtMs: Long,
    val revision: Long,
    val deviceId: String,
)

data class PwdlockConflictGroup(
    val groupId: String,
    val recordId: String,
    val state: String,
    val createdAtMs: Long,
)
