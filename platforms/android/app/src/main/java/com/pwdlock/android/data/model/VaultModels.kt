package com.pwdlock.android.data.model

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 登录项（UI 展示模型）。本地模式接入后，由 [PwdlockRecord] 经 [toVaultItem] 映射而来。
 * 组件中 [VaultItemRow] / [DetailRow] 等继续使用此模型，无需改动。
 */
data class VaultItem(
    val id: String,
    val title: String,
    val username: String,
    val password: String,
    val url: String,
    val category: String,
    val note: String,
    val updatedAt: String, // 展示用，如 "2026-07-12"
)

/** 冲突变体（本地版或导入版） */
data class ConflictVariant(
    val kind: String,        // "record" | "tombstone"
    val sourceVaultId: String,
    val sourceLabel: String, // 来源设备名，如 "Pixel 7"
    val title: String,
    val subtitle: String,    // 用户名 / "已删除"
    val updatedAt: String,
)

/** 冲突组：同一逻辑记录出现不同内容，待用户裁决 */
data class ConflictGroup(
    val id: String,
    val title: String,
    val variants: List<ConflictVariant>,
)

/** 导入摘要（导入预览页使用） */
data class ImportSummary(
    val added: Int,
    val skipped: Int,
    val conflict: Int,
    val tombstone: Int,
    val rejected: Int,
    val totalRecords: Int,
)

/** 将加密域模型 [PwdlockRecord] 映射为 UI 模型 [VaultItem]。 */
fun PwdlockRecord.toVaultItem(): VaultItem = VaultItem(
    id = id,
    title = title,
    username = username,
    password = password,
    url = url,
    category = category,
    note = note,
    updatedAt = formatDate(updatedAtMs),
)

fun formatDate(ms: Long): String =
    if (ms <= 0) "" else SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(ms))
