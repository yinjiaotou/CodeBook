package com.pwdlock.android.screen

import androidx.compose.foundation.background
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
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
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
import com.pwdlock.android.data.AppModePrefs
import com.pwdlock.android.data.vault.VaultSession
import com.pwdlock.android.navigation.Screen
import com.pwdlock.android.ui.components.AccentNote
import com.pwdlock.android.ui.components.NoteTone
import com.pwdlock.android.ui.components.PasswordField
import com.pwdlock.android.ui.components.PwdlockButton
import com.pwdlock.android.ui.components.PwdlockTopBar
import com.pwdlock.android.ui.theme.PwdlockColors
import com.pwdlock.android.ui.theme.ScreenHMargin
import com.pwdlock.android.ui.theme.SpaceLG
import com.pwdlock.android.ui.theme.SpaceMD
import com.pwdlock.android.ui.theme.SpaceXL
import com.pwdlock.android.ui.theme.SpaceSM
import androidx.compose.runtime.rememberCoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private fun strengthOf(pw: String): Int {
    if (pw.isEmpty()) return 0
    var score = 0
    if (pw.length >= 12) score++
    if (pw.length >= 16) score++
    if (pw.any { it.isUpperCase() } && pw.any { it.isLowerCase() }) score++
    if (pw.any { it.isDigit() }) score++
    if (pw.any { !it.isLetterOrDigit() }) score++
    return score.coerceIn(0, 4)
}

private fun strengthLabel(score: Int): String = when (score) {
    0 -> "太弱"
    1 -> "弱"
    2 -> "一般"
    3 -> "强"
    else -> "很强"
}

@Composable
fun CreateMasterPasswordScreen(navController: NavHostController) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val isChange = navController.currentBackStackEntry?.arguments?.getString("mode") == "change"

    var oldPassword by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var confirm by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }

    val strength = strengthOf(password)
    val meetsLength = password.length >= 12
    val match = password.isNotEmpty() && password == confirm
    val canCreate = meetsLength && match && !busy &&
        (!isChange || oldPassword.isNotEmpty())

    Scaffold(
        topBar = {
            PwdlockTopBar(
                title = if (isChange) "修改主密码" else "创建主密码",
                onBack = { navController.popBackStack() },
            )
        },
    ) { inner ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(inner)
                .padding(horizontal = ScreenHMargin, vertical = SpaceXL),
            verticalArrangement = Arrangement.spacedBy(SpaceLG),
        ) {
            Text(
                text = if (isChange) {
                    "输入当前主密码并设置新的主密码。记录数据不会被重新加密，仅重新包装 Vault Key。"
                } else {
                    "主密码用于加密本地密码库，且不会上传到任何服务器。"
                },
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            if (isChange) {
                PasswordField(
                    label = "当前主密码",
                    value = oldPassword,
                    onValueChange = { oldPassword = it; error = null },
                )
            }
            PasswordField(
                label = "主密码",
                value = password,
                onValueChange = { password = it; error = null },
            )
            PasswordField(
                label = "确认主密码",
                value = confirm,
                onValueChange = { confirm = it; error = null },
            )

            // 强度条
            Column(verticalArrangement = Arrangement.spacedBy(SpaceSM)) {
                Row(horizontalArrangement = Arrangement.spacedBy(SpaceSM)) {
                    repeat(4) { i ->
                        val active = i < strength
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .height(6.dp)
                                .clip(RoundedCornerShape(999.dp))
                                .background(
                                    if (active) {
                                        when (strength) {
                                            1 -> PwdlockColors.Danger
                                            2 -> PwdlockColors.Warning
                                            3 -> PwdlockColors.Success
                                            else -> PwdlockColors.Brand
                                        }
                                    } else {
                                        MaterialTheme.colorScheme.surfaceVariant
                                    },
                                ),
                        )
                    }
                }
                Text(
                    text = if (password.isEmpty()) "强度：${strengthLabel(0)}" else "强度：${strengthLabel(strength)}",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            if (!meetsLength && password.isNotEmpty()) {
                Text(
                    text = "主密码至少需要 12 个字符。",
                    style = MaterialTheme.typography.bodyMedium,
                    color = PwdlockColors.Danger,
                )
            }
            if (password.isNotEmpty() && confirm.isNotEmpty() && !match) {
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
                title = "请务必牢记主密码",
                text = "主密码遗失后，密码库不可恢复，也没有任何客服或找回通道。",
            )

            Spacer(modifier = Modifier.weight(1f))
            PwdlockButton(
                text = if (isChange) "确认修改" else "创建主密码",
                onClick = {
                    busy = true
                    error = null
                    scope.launch(Dispatchers.IO) {
                        try {
                            if (isChange) {
                                VaultSession.changeMasterPassword(context, oldPassword, password)
                                withContext(Dispatchers.Main) { navController.popBackStack() }
                            } else {
                                VaultSession.create(context, password)
                                AppModePrefs.setLastMode(context, "local")
                                withContext(Dispatchers.Main) {
                                    navController.navigate(Screen.VaultHome.route) {
                                        popUpTo(Screen.ModeSelect.route)
                                    }
                                }
                            }
                        } catch (e: Exception) {
                            withContext(Dispatchers.Main) {
                                error = if (isChange) "当前主密码错误" else "创建失败：${e.message}"
                                busy = false
                            }
                        }
                    }
                },
                enabled = canCreate,
            )
        }
    }
}
