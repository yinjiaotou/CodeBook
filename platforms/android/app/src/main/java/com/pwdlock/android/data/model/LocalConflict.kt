package com.pwdlock.android.data.model

/**
 * 本地待裁决冲突（参考 macOS `ImportConflict`）。
 *
 * 当导入的 `.pwdlock` 中存在与本地相同 `id` 但内容不同的记录时产生。
 * 冲突不会静默覆盖本地记录，需用户手动裁决（保留本地 / 用导入替换）。
 *
 * 仅存在于本地存储（`conflicts.enc`），不进入 `.pwdlock` 归档，保证跨端归档格式纯净。
 */
data class LocalConflict(
    val id: String,          // 冲突组 id（小写 UUID）
    val recordId: String,    // 冲突记录 id
    val title: String,       // 展示标题（取本地版）
    val createdAtMs: Long,   // 冲突产生时间
    val local: PwdlockRecord,
    val imported: PwdlockRecord,
)
