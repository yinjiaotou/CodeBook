package com.pwdlock.android.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.sp

/**
 * 临时字号体系。读取 ardot 稿子后按稿子字号/字重对齐。
 * 设计稿为移动端 390×844 画布，基准字号沿用 Material3 比例。
 */
val Typography = Typography(
    displaySmall = TextStyle(fontSize = 28.sp, lineHeight = 34.sp),
    titleLarge   = TextStyle(fontSize = 22.sp, lineHeight = 28.sp),
    titleMedium  = TextStyle(fontSize = 18.sp, lineHeight = 24.sp),
    bodyLarge    = TextStyle(fontSize = 16.sp, lineHeight = 24.sp),
    bodyMedium   = TextStyle(fontSize = 14.sp, lineHeight = 20.sp),
    labelLarge   = TextStyle(fontSize = 14.sp, lineHeight = 20.sp),
    labelMedium  = TextStyle(fontSize = 12.sp, lineHeight = 16.sp),
)
