package com.pwdlock.android.screen

import android.os.Build
import android.widget.Toast
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.selection.selectable
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import com.pwdlock.android.data.AppModePrefs
import com.pwdlock.android.data.online.OnlineAccountStore
import com.pwdlock.android.data.settings.SettingsStore
import com.pwdlock.android.data.vault.BiometricUnlock
import com.pwdlock.android.data.vault.OnlineBiometricUnlock
import com.pwdlock.android.data.vault.VaultSession
import com.pwdlock.android.navigation.Screen
import com.pwdlock.android.navigation.navigateToModeSelect
import com.pwdlock.android.ui.components.PwdlockTopBar
import com.pwdlock.android.ui.theme.PwdlockColors
import com.pwdlock.android.ui.theme.ScreenHMargin
import com.pwdlock.android.ui.theme.SpaceMD
import com.pwdlock.android.ui.theme.SpaceSM
import com.pwdlock.android.ui.theme.SpaceXL

@Composable
fun SettingsScreen(navController: NavHostController) {
    val context = LocalContext.current
    val store = remember { SettingsStore(context) }

    // 当前激活模式：在线模式指纹走 OnlineBiometricUnlock，本地模式走 BiometricUnlock（两套隔离）。
    val isOnline = VaultSession.onlineMode

    // 生物识别状态（设备支持时才展示；enable/disable 为异步，成功后回读刷新）。
    // 初始开关状态按当前模式从各自存储读取，避免本地/在线凭据串台。
    val bioSupported = remember { BiometricUnlock.deviceSupported(context) }
    var bioEnabled by remember {
        mutableStateOf(if (isOnline) OnlineBiometricUnlock.isEnabled(context) else store.biometricEnabled)
    }

    // 自动锁定
    var autoLockMinutes by remember { mutableStateOf(store.autoLockMinutes) }
    var showAutoLockDialog by remember { mutableStateOf(false) }

    // 冲突数量（实时）
    val conflicts by VaultSession.conflicts.collectAsState()

    // 在线账户区：仅在本会话处于「在线模式」时展示。
    // 必须以当前激活模式 VaultSession.onlineMode 为准，而非「是否存在 token」——
    // 否则即便切回本地模式，残留的在线 token 仍会让本地设置页混入在线账户 / 同步等 UI。

    Scaffold(
        topBar = { PwdlockTopBar(title = "设置", onBack = { navController.popBackStack() }) },
    ) { inner ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(inner)
                .verticalScroll(rememberScrollState())
                .padding(vertical = SpaceXL),
        ) {
            SectionTitle("安全")
            ClickRow("修改主密码") {
                navController.navigate("create_master_password?mode=change")
            }
            if (bioSupported) {
                SwitchRow(
                    label = "指纹解锁",
                    checked = bioEnabled,
                ) { wantEnable ->
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return@SwitchRow
                    // 在线 / 本地两套独立指纹凭据，按当前激活模式分派。
                    val onDone = {
                        bioEnabled = true
                        Toast.makeText(context, "已开启指纹解锁", Toast.LENGTH_SHORT).show()
                    }
                    val onErr = { msg: String ->
                        bioEnabled = false
                        Toast.makeText(context, msg, Toast.LENGTH_LONG).show()
                    }
                    if (wantEnable) {
                        if (isOnline) {
                            OnlineBiometricUnlock.enable(
                                context = context,
                                onDone = onDone,
                                onError = onErr,
                                onCancel = { bioEnabled = false },
                            )
                        } else {
                            BiometricUnlock.enable(
                                context = context,
                                onDone = onDone,
                                onError = onErr,
                                onCancel = { bioEnabled = false },
                            )
                        }
                    } else {
                        if (isOnline) OnlineBiometricUnlock.disable(context) else BiometricUnlock.disable(context)
                        bioEnabled = false
                        Toast.makeText(context, "已关闭指纹解锁", Toast.LENGTH_SHORT).show()
                    }
                }
            }
            ClickRow("自动锁定") {
                showAutoLockDialog = true
            }

            SectionTitle("数据")
            ClickRow("导入 / 导出") {
                navController.navigate(Screen.ImportExport.route)
            }
            // 冲突中心为本地模式导入合并能力；在线模式无冲突概念，不展示该入口。
            if (!VaultSession.onlineMode) {
                ClickRow(
                    label = "冲突中心",
                    trailing = if (conflicts.isNotEmpty()) {
                        {
                            Text(
                                text = "${conflicts.size}",
                                style = MaterialTheme.typography.bodyLarge,
                                color = PwdlockColors.Warning,
                            )
                        }
                    } else null,
                    onClick = { navController.navigate(Screen.ConflictCenter.route) },
                )
            }

            SectionTitle("关于")
            ClickRow("关于 Pwdlock") {
                navController.navigate(Screen.About.route)
            }

            if (isOnline) {
                SectionTitle("在线账户")
                ClickRow(
                    label = "当前账号",
                    subtitle = OnlineAccountStore.loginName(context) ?: "",
                ) {}
                ClickRow(
                    label = "退出登录",
                    subtitle = "清除本机账户与密钥缓存",
                ) {
                    VaultSession.logoutOnline(context)
                    Toast.makeText(context, "已退出登录", Toast.LENGTH_SHORT).show()
                    navController.navigateToModeSelect()
                }
            }

            SectionTitle("运行模式")
            if (isOnline) {
                // 当前在线模式：提供切回本地。按本机是否已有本地库跳对应首屏。
                ClickRow("切换为本地模式") {
                    AppModePrefs.setLastMode(context, "local")
                    val localRoute =
                        if (VaultSession.hasVault(context)) Screen.Unlock.route else "create_master_password"
                    navController.navigate(localRoute) {
                        popUpTo(Screen.ModeSelect.route) { inclusive = true }
                        launchSingleTop = true
                    }
                }
            } else {
                // 当前本地模式：提供切到线上。按本机是否仍存有在线登录信息（token）决定
                // 直接进入主密码解锁页（免重登）还是先到登录页。
                ClickRow("切换为线上模式") {
                    AppModePrefs.setLastMode(context, "online")
                    val onlineRoute =
                        if (OnlineAccountStore.hasToken(context)) Screen.OnlineMasterPassword.route else Screen.OnlineLogin.route
                    navController.navigate(onlineRoute) {
                        popUpTo(Screen.ModeSelect.route) { inclusive = true }
                        launchSingleTop = true
                    }
                }
            }
        }
    }

    if (showAutoLockDialog) {
        AutoLockDialog(
            current = autoLockMinutes,
            onSelect = { minutes ->
                autoLockMinutes = minutes
                store.autoLockMinutes = minutes
                showAutoLockDialog = false
            },
            onDismiss = { showAutoLockDialog = false },
        )
    }
}

@Composable
private fun AutoLockDialog(
    current: Int,
    onSelect: (Int) -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("前台闲置锁定") },
        text = {
            Column {
                SettingsStore.AUTOLOCK_OPTIONS.forEach { minutes ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .selectable(
                                selected = minutes == current,
                                onClick = { onSelect(minutes) },
                            )
                            .padding(vertical = SpaceSM),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        RadioButton(selected = minutes == current, onClick = { onSelect(minutes) })
                        Text(
                            text = SettingsStore.autoLockLabel(minutes),
                            style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onSurface,
                            modifier = Modifier.padding(start = SpaceSM),
                        )
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text("完成") }
        },
    )
}

@Composable
private fun SectionTitle(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(horizontal = ScreenHMargin, vertical = SpaceSM),
    )
}

@Composable
private fun ClickRow(
    label: String,
    subtitle: String? = null,
    trailing: (@Composable () -> Unit)? = null,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = ScreenHMargin, vertical = SpaceMD),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(label, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurface)
            if (!subtitle.isNullOrBlank()) {
                Text(
                    subtitle,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        trailing?.invoke()
    }
    HorizontalDivider(color = MaterialTheme.colorScheme.outline, thickness = 1.dp, modifier = Modifier.padding(start = ScreenHMargin))
}

@Composable
private fun SwitchRow(
    label: String,
    subtitle: String? = null,
    checked: Boolean,
    onToggle: (Boolean) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = ScreenHMargin, vertical = SpaceMD),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(label, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurface)
            if (!subtitle.isNullOrBlank()) {
                Text(
                    subtitle,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        Switch(checked = checked, onCheckedChange = onToggle)
    }
    HorizontalDivider(color = MaterialTheme.colorScheme.outline, thickness = 1.dp, modifier = Modifier.padding(start = ScreenHMargin))
}
