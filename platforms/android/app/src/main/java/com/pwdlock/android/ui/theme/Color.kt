package com.pwdlock.android.ui.theme

import androidx.compose.ui.graphics.Color

/**
 * Pwdlock 设计色板（静态阶段占位，待读取 ardot 稿子后对齐）。
 * 基调：沉稳蓝（信任/安全）+ 中性灰阶 + 语义色。
 */
object PwdlockColors {
    // 品牌主色
    val Brand = Color(0xFF3B6EF6)
    val BrandDark = Color(0xFF5B8DEF)
    val BrandContainer = Color(0xFFE3ECFF)
    val OnBrandContainer = Color(0xFF0B3AA8)

    // 语义色
    val Success = Color(0xFF1FA971)
    val SuccessContainer = Color(0xFFD6F2E6)
    val Warning = Color(0xFFE0A03A)
    val WarningContainer = Color(0xFFFBEFD5)
    val Danger = Color(0xFFE5484D)
    val DangerContainer = Color(0xFFFBDADA)

    // 文字 / 图标（浅色背景）
    val Ink900 = Color(0xFF10141B)
    val Ink700 = Color(0xFF3A414C)
    val Ink500 = Color(0xFF6B7280)
    val Ink300 = Color(0xFFAEB4BE)

    // 表面（浅色）
    val SurfaceBG = Color(0xFFF6F7F9)
    val Surface = Color(0xFFFFFFFF)
    val SurfaceVariant = Color(0xFFF0F2F5)
    val Divider = Color(0xFFE3E6EB)
}
