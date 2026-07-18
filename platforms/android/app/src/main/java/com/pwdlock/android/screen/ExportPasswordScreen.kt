package com.pwdlock.android.screen

import android.util.Log
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import com.pwdlock.android.data.vault.VaultSession
import com.pwdlock.android.navigation.Screen
import com.pwdlock.android.ui.components.AccentNote
import com.pwdlock.android.ui.components.NoteTone
import com.pwdlock.android.ui.components.PasswordField
import com.pwdlock.android.ui.components.PwdlockButton
import com.pwdlock.android.ui.components.PwdlockTopBar
import com.pwdlock.android.ui.theme.PwdlockColors
import com.pwdlock.android.ui.theme.RadiusMD
import com.pwdlock.android.ui.theme.ScreenHMargin
import com.pwdlock.android.ui.theme.SpaceLG
import com.pwdlock.android.ui.theme.SpaceMD
import com.pwdlock.android.ui.theme.SpaceXL
import androidx.compose.runtime.rememberCoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.IOException
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
fun ExportPasswordScreen(navController: NavHostController) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val snackbar = remember { SnackbarHostState() }
    var exportPassword by remember { mutableStateOf("") }
    var confirm by remember { mutableStateOf("") }
    var exported by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    // 跨「系统创建文档」选择器暂存待写入的密文（选择器返回时再落盘到用户所选位置）。
    val pendingBytes = remember { mutableStateOf<ByteArray?>(null) }

    val saver = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/octet-stream")) { uri ->
        if (uri == null) {
            // 用户取消保存
            busy = false
            return@rememberLauncherForActivityResult
        }
        try {
            context.contentResolver.openOutputStream(uri)?.use { out ->
                out.write(pendingBytes.value)
            } ?: throw IOException("无法打开输出流")
            pendingBytes.value = null
            exported = true
        } catch (e: Exception) {
            Log.e("Export", "write to uri failed", e)
            error = "保存失败：${e.message ?: "未知错误"}"
            busy = false
        }
    }

    LaunchedEffect(exported) {
        if (!exported) return@LaunchedEffect
        snackbar.showSnackbar("导出成功，文件已保存到所选位置")
        delay(1200)
        navController.popBackStack()
    }

    Scaffold(
        topBar = { PwdlockTopBar(title = "导出设密", onBack = { navController.popBackStack() }) },
        snackbarHost = { SnackbarHost(snackbar) },
    ) { inner ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(inner)
                .padding(horizontal = ScreenHMargin, vertical = SpaceXL),
            verticalArrangement = Arrangement.spacedBy(SpaceLG),
        ) {
            Text(
                text = "为导出的 .pwdlock 文件设置一个独立的导出密码。",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            PasswordField(label = "导出密码", value = exportPassword, onValueChange = { exportPassword = it; error = null })
            PasswordField(label = "确认导出密码", value = confirm, onValueChange = { confirm = it; error = null })

            if (!exportPasswordMeetsLength(exportPassword) && exportPassword.isNotEmpty()) {
                Text(
                    text = "导出密码至少需要 12 个字符。",
                    style = MaterialTheme.typography.bodyMedium,
                    color = PwdlockColors.Danger,
                )
            }
            if (exportPassword.isNotEmpty() && confirm.isNotEmpty() && exportPassword != confirm) {
                Text(
                    text = "两次输入的密码不一致。",
                    style = MaterialTheme.typography.bodyMedium,
                    color = PwdlockColors.Danger,
                )
            }
            if (error != null) {
                Text(
                    text = error!!,
                    style = MaterialTheme.typography.bodyMedium,
                    color = PwdlockColors.Danger,
                )
            }

            AccentNote(
                icon = Icons.Filled.Warning,
                tone = NoteTone.Warning,
                title = "不要复用主密码",
                text = "导出密码独立于主密码，且不会预填。记住它——没有它，导出文件无法恢复。",
            )

            Spacer(modifier = Modifier.weight(1f))
            PwdlockButton(
                text = if (busy) "正在导出…" else "开始导出",
                onClick = {
                    busy = true
                    error = null
                    scope.launch(Dispatchers.IO) {
                        try {
                            // 1) 用导出密码加密生成密文（需要 vault 已解锁）。
                            val bytes = VaultSession.export(exportPassword)
                            val ts = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(Date())
                            withContext(Dispatchers.Main) {
                                // 2) 弹出系统「保存到哪里」选择器，让用户把文件存到可见位置（如 Download）。
                                pendingBytes.value = bytes
                                saver.launch("$ts.pwdlock")
                            }
                        } catch (e: Exception) {
                            Log.e("Export", "export failed", e)
                            withContext(Dispatchers.Main) {
                                busy = false
                                error = "导出失败：${e.message ?: "未知错误"}"
                            }
                        }
                    }
                },
                enabled = exportPasswordMeetsLength(exportPassword) && exportPassword == confirm && !busy,
            )
        }
    }
}

/** 导出密码强度要求：至少 12 字符。 */
private fun exportPasswordMeetsLength(p: String): Boolean = p.length >= 12
