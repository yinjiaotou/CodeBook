package com.pwdlock.android.screen

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import android.util.Log
import android.widget.Toast
import com.pwdlock.android.data.model.PwdlockPayload
import com.pwdlock.android.data.vault.VaultSession
import com.pwdlock.android.navigation.Screen
import com.pwdlock.android.ui.components.LoadingOverlay
import com.pwdlock.android.ui.components.PasswordField
import com.pwdlock.android.ui.components.PwdlockButton
import com.pwdlock.android.ui.components.PwdlockTopBar
import com.pwdlock.android.ui.theme.PwdlockColors
import com.pwdlock.android.ui.theme.ScreenHMargin
import com.pwdlock.android.ui.theme.SpaceLG
import com.pwdlock.android.ui.theme.SpaceXL
import com.pwdlock.android.ui.theme.SpaceSM
import androidx.compose.runtime.rememberCoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun ImportPreviewScreen(navController: NavHostController) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var password by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var importing by remember { mutableStateOf(false) }

    // 导入流程进行中：豁免自动锁定，确保确认时 vaultKey 在线、不被打断。
    // 注意：本页不在 onDispose 复位 importFlowActive —— 复位由导入/导出页（ImportExportScreen）
    // 在其自身销毁时统一执行，避免从预览返回导出页后标志被提前清零、重新暴露于自动锁定之下。
    DisposableEffect(Unit) {
        VaultSession.importFlowActive = true
        onDispose { }
    }

    Scaffold(
        topBar = { PwdlockTopBar(title = "导入保险库", onBack = { navController.popBackStack() }) },
    ) { inner ->
        Box(modifier = Modifier.fillMaxSize()) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(inner)
                    .padding(horizontal = ScreenHMargin, vertical = SpaceXL),
                verticalArrangement = Arrangement.spacedBy(SpaceLG),
            ) {
                Text(
                    text = "输入该 .pwdlock 文件的导出密码以解密并导入。导入后数据会与本地保险库合并，冲突项会被保留待你裁决。",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                PasswordField(
                    label = "导出密码",
                    value = password,
                    onValueChange = { password = it; error = null },
                )
                if (error != null) {
                    Text(
                        text = error!!,
                        style = MaterialTheme.typography.bodyMedium,
                        color = PwdlockColors.Danger,
                    )
                }
                Spacer(modifier = Modifier.weight(1f))
                PwdlockButton(
                    text = if (importing) "正在导入…" else "确认",
                    enabled = password.isNotBlank() && !importing,
                    onClick = {
                        // 先把 loading 顶上来，阻止重复点击；导入完成后再做跳转。
                        importing = true
                        error = null
                        scope.launch(Dispatchers.IO) {
                            // 1) 解密（导出密码错误会抛异常，留在当前页让用户重试）
                            var payload: PwdlockPayload? = null
                            try {
                                payload = VaultSession.importPreview(password)
                            } catch (e: Exception) {
                                withContext(Dispatchers.Main) {
                                    importing = false
                                    error = "导出密码错误或文件损坏"
                                }
                                return@launch
                            }
                            // 2) 合并导入（用本地 vaultKey 重新加密 = 重置主密码）。
                            //    无论成功失败都不锁定，直接显示密码库；有冲突则进入冲突界面。
                            try {
                                val result = VaultSession.mergeImport(context, payload)
                                VaultSession.clearPendingImport()
                                VaultSession.pendingMergePayload = null
                                withContext(Dispatchers.Main) {
                                    val msg = if (result.conflicts > 0) {
                                        "导入成功，存在 ${result.conflicts} 个冲突待处理"
                                    } else {
                                        "导入成功"
                                    }
                                    Toast.makeText(context, msg, Toast.LENGTH_SHORT).show()
                                    importing = false
                                    if (result.conflicts > 0) {
                                        // 有冲突：直接进入冲突界面，裁决完成后再进密码库刷新数据。
                                        navController.navigate(Screen.ConflictCenter.route) {
                                            popUpTo(Screen.ModeSelect.route)
                                        }
                                    } else {
                                        // 无冲突：进入密码库（StateFlow 已更新，自动刷新）。
                                        navController.navigate(Screen.VaultHome.route) {
                                            popUpTo(Screen.ModeSelect.route)
                                        }
                                    }
                                }
                            } catch (e: Exception) {
                                Log.e("ImportConfirm", "mergeImport failed", e)
                                VaultSession.clearPendingImport()
                                VaultSession.pendingMergePayload = null
                                withContext(Dispatchers.Main) {
                                    importing = false
                                    Toast.makeText(context, "导入失败", Toast.LENGTH_SHORT).show()
                                    navController.navigate(Screen.VaultHome.route) {
                                        popUpTo(Screen.ModeSelect.route)
                                    }
                                }
                            }
                        }
                    },
                )
            }

            if (importing) {
                LoadingOverlay(text = "正在导入…")
            }
        }
    }
}
