package com.pwdlock.android.screen

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import android.widget.Toast
import com.pwdlock.android.data.network.ApiException
import com.pwdlock.android.data.vault.VaultSession
import com.pwdlock.android.navigation.Screen
import com.pwdlock.android.ui.components.AccentNote
import com.pwdlock.android.ui.components.LoadingOverlay
import com.pwdlock.android.ui.components.NoteTone
import com.pwdlock.android.ui.components.PasswordField
import com.pwdlock.android.ui.components.PwdlockButton
import com.pwdlock.android.ui.components.PwdlockTextField
import com.pwdlock.android.ui.components.PwdlockTopBar
import com.pwdlock.android.ui.theme.PwdlockColors
import com.pwdlock.android.ui.theme.RadiusPill
import com.pwdlock.android.ui.theme.ScreenHMargin
import com.pwdlock.android.ui.theme.SpaceLG
import com.pwdlock.android.ui.theme.SpaceMD
import com.pwdlock.android.ui.theme.SpaceSM
import com.pwdlock.android.ui.theme.SpaceXL
import kotlinx.coroutines.launch

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
fun OnlineRegisterScreen(navController: NavHostController) {
    var account by remember { mutableStateOf("") }
    var loginPassword by remember { mutableStateOf("") }
    var loginConfirm by remember { mutableStateOf("") }
    var masterPassword by remember { mutableStateOf("") }
    var masterConfirm by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    val accountOk = account.isNotBlank() && account.contains("@")
    val loginOk = loginPassword.length >= 12 && loginPassword == loginConfirm
    val masterStrength = strengthOf(masterPassword)
    val masterMeetsLength = masterPassword.length >= 12
    val masterOk = masterMeetsLength && masterPassword == masterConfirm
    val canRegister = accountOk && loginOk && masterOk

    Scaffold(
        topBar = {
            PwdlockTopBar(title = "注册", onBack = { navController.popBackStack() })
        },
    ) { inner ->
        Box(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(inner)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = ScreenHMargin, vertical = SpaceXL),
            verticalArrangement = Arrangement.spacedBy(SpaceLG),
        ) {
            Text(
                text = "注册在线账户：登录凭证用于同步，主密码用于加密你的保险库，两者相互独立。",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            // 登录凭证
            PwdlockTextField(
                label = "账号 / 邮箱",
                value = account,
                onValueChange = { account = it },
                keyboardType = KeyboardType.Email,
            )
            PasswordField(
                label = "登录密码",
                value = loginPassword,
                onValueChange = { loginPassword = it },
            )
            PasswordField(
                label = "确认登录密码",
                value = loginConfirm,
                onValueChange = { loginConfirm = it },
            )
            if (loginPassword.isNotEmpty() && loginConfirm.isNotEmpty() && !loginOk) {
                Text(
                    text = "两次输入的登录密码不一致，或少于 12 个字符。",
                    style = MaterialTheme.typography.bodyMedium,
                    color = PwdlockColors.Danger,
                )
            }

            // 保险库主密码
            PasswordField(
                label = "主密码",
                value = masterPassword,
                onValueChange = { masterPassword = it },
            )
            PasswordField(
                label = "确认主密码",
                value = masterConfirm,
                onValueChange = { masterConfirm = it },
            )

            Column(verticalArrangement = Arrangement.spacedBy(SpaceSM)) {
                Row(horizontalArrangement = Arrangement.spacedBy(SpaceSM)) {
                    repeat(4) { i ->
                        val active = i < masterStrength
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .height(6.dp)
                                .clip(RoundedCornerShape(RadiusPill))
                                .background(
                                    if (active) {
                                        when (masterStrength) {
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
                    text = if (masterPassword.isEmpty()) "强度：${strengthLabel(0)}" else "强度：${strengthLabel(masterStrength)}",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (masterPassword.isNotEmpty() && !masterMeetsLength) {
                Text(
                    text = "主密码至少需要 12 个字符。",
                    style = MaterialTheme.typography.bodyMedium,
                    color = PwdlockColors.Danger,
                )
            }
            if (masterPassword.isNotEmpty() && masterConfirm.isNotEmpty() && masterPassword != masterConfirm) {
                Text(
                    text = "两次输入的主密码不一致。",
                    style = MaterialTheme.typography.bodyMedium,
                    color = PwdlockColors.Danger,
                )
            }

            AccentNote(
                icon = Icons.Filled.Cloud,
                tone = NoteTone.Info,
                title = "账号与保险库相互独立",
                text = "服务器仅保存主密码加密后的数据；登录密码用于同步，主密码用于解密，二者不可互相替代，请务必牢记主密码。",
            )

            Spacer(modifier = Modifier.height(SpaceMD))
            PwdlockButton(
                text = "注册并进入",
                enabled = canRegister && !loading,
                onClick = {
                    scope.launch {
                        loading = true
                        try {
                            VaultSession.registerOnline(context, account.trim(), loginPassword, masterPassword)
                            loading = false
                            navController.navigate(Screen.VaultHome.route)
                        } catch (e: Exception) {
                            loading = false
                            val msg = if (e is ApiException.Conflict) {
                                "账号已存在，请直接登录"
                            } else {
                                "注册失败：${e.message ?: e.javaClass.simpleName}"
                            }
                            Toast.makeText(context, msg, Toast.LENGTH_LONG).show()
                        }
                    }
                },
            )

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(onClick = { navController.navigate(Screen.OnlineLogin.route) }),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "已有账号？",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(modifier = Modifier.padding(start = SpaceSM))
                Text(
                    text = "登录",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
        }
        if (loading) LoadingOverlay("注册中…")
        }
    }
}
