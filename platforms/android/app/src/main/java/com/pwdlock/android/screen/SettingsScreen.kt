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
import androidx.compose.material3.OutlinedTextField
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
import com.pwdlock.android.data.online.OnlineAccountStore
import com.pwdlock.android.data.settings.SettingsStore
import com.pwdlock.android.data.vault.BiometricUnlock
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

    // 生物识别状态（设备支持时才展示；enable/disable 为异步，成功后回读刷新）。
    val bioSupported = remember { BiometricUnlock.deviceSupported(context) }
    var bioEnabled by remember { mutableStateOf(store.biometricEnabled) }

    // 自动锁定
    var autoLockMinutes by remember { mutableStateOf(store.autoLockMinutes) }
    var lockOnBackground by remember { mutableStateOf(store.lockOnBackground) }
    var showAutoLockDialog by remember { mutableStateOf(false) }

    // 冲突数量（实时）
    val conflicts by VaultSession.conflicts.collectAsState()

    // 在线账户区：仅在已登录时展示。
    val onlineLoggedIn = remember { OnlineAccountStore.hasToken(context) }
    var showBaseUrlDialog by remember { mutableStateOf(false) }

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
                    if (wantEnable) {
                        BiometricUnlock.enable(
                            context = context,
                            onDone = {
                                bioEnabled = true
                                Toast.makeText(context, "已开启指纹解锁", Toast.LENGTH_SHORT).show()
                            },
                            onError = { msg ->
                                bioEnabled = false
                                Toast.makeText(context, msg, Toast.LENGTH_LONG).show()
                            },
                            onCancel = { bioEnabled = false },
                        )
                    } else {
                        BiometricUnlock.disable(context)
                        bioEnabled = false
                        Toast.makeText(context, "已关闭指纹解锁", Toast.LENGTH_SHORT).show()
                    }
                }
            }
            ClickRow("自动锁定") {
                showAutoLockDialog = true
            }
            SwitchRow(
                label = "切到后台时锁定",
                checked = lockOnBackground,
            ) {
                lockOnBackground = it
                store.lockOnBackground = it
            }

            SectionTitle("数据")
            ClickRow("导入 / 导出") {
                navController.navigate(Screen.ImportExport.route)
            }
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

            SectionTitle("关于")
            ClickRow("关于 Pwdlock") {
                navController.navigate(Screen.About.route)
            }

            if (onlineLoggedIn) {
                SectionTitle("在线账户")
                ClickRow(
                    label = "当前账号",
                    subtitle = OnlineAccountStore.loginName(context) ?: "",
                ) {}
                ClickRow(
                    label = "上次同步",
                    subtitle = formatSyncTime(OnlineAccountStore.lastSyncMs(context)),
                ) {}
                ClickRow(
                    label = "服务地址",
                    subtitle = OnlineAccountStore.baseUrl(context),
                ) { showBaseUrlDialog = true }
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
            ClickRow("切换运行模式") {
                navController.navigateToModeSelect()
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

    if (showBaseUrlDialog) {
        var url by remember { mutableStateOf(OnlineAccountStore.baseUrl(context)) }
        AlertDialog(
            onDismissRequest = { showBaseUrlDialog = false },
            title = { Text("服务地址") },
            text = {
                OutlinedTextField(
                    value = url,
                    onValueChange = { url = it },
                    label = { Text("URL") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    OnlineAccountStore.setBaseUrl(context, url.trim())
                    showBaseUrlDialog = false
                    Toast.makeText(context, "已保存服务地址", Toast.LENGTH_SHORT).show()
                }) { Text("保存") }
            },
            dismissButton = {
                TextButton(onClick = { showBaseUrlDialog = false }) { Text("取消") }
            },
        )
    }
}

/** 格式化同步时间（毫秒 → 可读字符串）。 */
private fun formatSyncTime(ms: Long): String {
    if (ms <= 0) return "尚未同步"
    val sdf = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm", java.util.Locale.getDefault())
    return sdf.format(java.util.Date(ms))
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
