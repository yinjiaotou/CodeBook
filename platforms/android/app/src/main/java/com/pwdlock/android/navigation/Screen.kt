package com.pwdlock.android.navigation

/**
 * 应用内路由表。当前为静态页面阶段，所有页面均为无参路由。
 * 后续接入加密/数据库逻辑时再补充参数（如 itemId、conflictGroupId）。
 */
sealed class Screen(
    val route: String,
    val label: String,
) {
    data object ModeSelect : Screen("mode_select", "选择模式")
    data object Welcome : Screen("welcome", "欢迎")
    data object OnlineLogin : Screen("online_login", "登录")
    data object OnlineMasterPassword : Screen("online_master_password", "输入主密码")
    data object OnlineRegister : Screen("online_register", "注册")
    data object CreateMasterPassword : Screen("create_master_password?mode={mode}", "创建主密码")
    data object Unlock : Screen("unlock", "解锁")
    data object VaultHome : Screen("vault_home", "密码库")
    data object ItemDetail : Screen("item_detail/{itemId}", "登录项详情")
    data object ItemEdit : Screen("item_edit?itemId={itemId}", "新增 / 编辑登录项")
    data object Settings : Screen("settings", "设置")
    data object ImportExport : Screen("import_export", "导入 / 导出")
    data object ExportPassword : Screen("export_password", "导出设密")
    data object ImportPreview : Screen("import_preview", "导入保险库")
    data object PasswordGenerator : Screen("password_generator", "密码生成器")
    data object ConflictCenter : Screen("conflict_center", "冲突中心")
    data object About : Screen("about", "关于")
    data object AutoLock : Screen("auto_lock", "已锁定")
}
