package com.pwdlock.android.navigation

import androidx.navigation.NavHostController

/**
 * 统一跳转到「选择模式」首屏，并清空此前所有路由历史。
 * 避免从任意页面返回时触发无限返回（例如 设置→切换运行模式 直接 navigate 会把新的
 * ModeSelect 压在旧历史之上，导致 设置↔密码库↔旧ModeSelect 循环）。
 */
fun NavHostController.navigateToModeSelect() {
    navigate(Screen.ModeSelect.route) {
        // 清除到首屏（含首屏自身），再重新压入，使 ModeSelect 成为栈中唯一页面。
        popUpTo(graph.startDestinationId) { inclusive = true }
        launchSingleTop = true
    }
}
