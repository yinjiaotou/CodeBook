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
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.CloudOff
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Logout
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import android.os.Build
import android.widget.Toast
import androidx.navigation.NavHostController
import com.pwdlock.android.data.network.ApiException
import com.pwdlock.android.data.AppModePrefs
import com.pwdlock.android.data.online.OnlineAccountStore
import com.pwdlock.android.data.vault.OnlineBiometricUnlock
import com.pwdlock.android.data.vault.VaultSession
import com.pwdlock.android.navigation.Screen
import com.pwdlock.android.ui.components.LoadingOverlay
import com.pwdlock.android.ui.components.PasswordField
import com.pwdlock.android.ui.components.PwdlockButton
import com.pwdlock.android.ui.components.PwdlockOutlinedButton
import com.pwdlock.android.ui.theme.PwdlockColors
import com.pwdlock.android.ui.theme.RadiusLG
import com.pwdlock.android.ui.theme.RadiusPill
import com.pwdlock.android.ui.theme.ScreenHMargin
import com.pwdlock.android.ui.theme.SpaceLG
import com.pwdlock.android.ui.theme.SpaceMD
import com.pwdlock.android.ui.theme.SpaceSM
import com.pwdlock.android.ui.theme.SpaceXL
import com.pwdlock.android.ui.theme.SpaceXXL
import kotlinx.coroutines.launch

private fun masterStrength(pw: String): Int {
    if (pw.isEmpty()) return 0
    var score = 0
    if (pw.length >= 12) score++
    if (pw.length >= 16) score++
    if (pw.any { it.isUpperCase() } && pw.any { it.isLowerCase() }) score++
    if (pw.any { it.isDigit() }) score++
    if (pw.any { !it.isLetterOrDigit() }) score++
    return score.coerceIn(0, 4)
}

private fun masterStrengthLabel(score: Int): String = when (score) {
    0 -> "太弱"
    1 -> "弱"
    2 -> "一般"
    3 -> "强"
    else -> "很强"
}

@Composable
fun OnlineMasterPasswordScreen(navController: NavHostController) {
    var password by remember { mutableStateOf("") }
    var confirm by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val loggedInAccount = OnlineAccountStore.loginName(context) ?: ""
    // 是否持有在线登录信息（token）。持有即表示已登录，可展示「退出当前登录」。
    val hasLogin = OnlineAccountStore.hasToken(context)

    // 无 vaultId 表示本次登录的账户在云端还没有保险库（从未创建过主密码）。
    // 与 Mac 端一致：此时本页是「创建主密码 / 创建保险库」流程，而非「解锁」。
    val createMode = OnlineAccountStore.vaultId(context).isBlank()

    val meetsLength = password.length >= 12
    val match = password == confirm
    val canSubmit = if (createMode) meetsLength && match else password.isNotBlank()
    val strength = masterStrength(password)

    Box(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(MaterialTheme.colorScheme.background)
                .padding(horizontal = ScreenHMargin, vertical = SpaceXL),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Box(
                modifier = Modifier
                    .size(72.dp)
                    .clip(RoundedCornerShape(RadiusLG))
                    .background(PwdlockColors.BrandContainer),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Filled.Lock,
                    contentDescription = null,
                    tint = PwdlockColors.Brand,
                    modifier = Modifier.size(38.dp),
                )
                // 右上角云端图标：用于在视觉上标识当前为「在线模式」。
                Icon(
                    imageVector = Icons.Filled.Cloud,
                    contentDescription = null,
                    tint = PwdlockColors.Brand,
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .offset(x = 7.dp, y = (-7).dp)
                        .size(26.dp)
                        .clip(CircleShape)
                        .background(MaterialTheme.colorScheme.background)
                        .padding(4.dp),
                )
            }

            Spacer(modifier = Modifier.height(SpaceXL))
            Text(
                text = if (createMode) "创建你的保险库" else loggedInAccount,
                style = MaterialTheme.typography.titleLarge,
                color = MaterialTheme.colorScheme.onBackground,
            )
            Text(
                text = if (createMode) {
                    "为你的在线保险库设置主密码，用于加密全部数据。请务必牢记，我们无法帮你找回。"
                } else {
                    "输入主密码以解密云端保险库"
                },
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )

            Spacer(modifier = Modifier.height(SpaceXL))
            PasswordField(
                label = if (createMode) "设置主密码" else "主密码",
                value = password,
                onValueChange = { password = it },
            )
            if (createMode) {
                Spacer(modifier = Modifier.height(SpaceMD))
                PasswordField(
                    label = "确认主密码",
                    value = confirm,
                    onValueChange = { confirm = it },
                )
                Spacer(modifier = Modifier.height(SpaceSM))
                Row(horizontalArrangement = Arrangement.spacedBy(SpaceSM)) {
                    repeat(4) { i ->
                        val active = i < strength
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .height(6.dp)
                                .clip(RoundedCornerShape(RadiusPill))
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
                Spacer(modifier = Modifier.height(SpaceSM))
                Text(
                    text = if (password.isEmpty()) "强度：${masterStrengthLabel(0)}" else "强度：${masterStrengthLabel(strength)}",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (password.isNotEmpty() && !meetsLength) {
                    Spacer(modifier = Modifier.height(SpaceSM))
                    Text(
                        text = "主密码至少需要 12 个字符。",
                        style = MaterialTheme.typography.bodyMedium,
                        color = PwdlockColors.Danger,
                    )
                }
                if (password.isNotEmpty() && confirm.isNotEmpty() && !match) {
                    Spacer(modifier = Modifier.height(SpaceSM))
                    Text(
                        text = "两次输入的主密码不一致。",
                        style = MaterialTheme.typography.bodyMedium,
                        color = PwdlockColors.Danger,
                    )
                }
            }

            Spacer(modifier = Modifier.height(SpaceLG))
            PwdlockButton(
                text = if (createMode) "创建并进入" else "解锁",
                enabled = canSubmit && !loading,
                onClick = {
                    scope.launch {
                        loading = true
                        try {
                            VaultSession.unlockOnline(context, password)
                            navController.navigate(Screen.VaultHome.route) {
                                // 与本地解锁对齐：进入密码库后清掉 ModeSelect 以下的历史，
                                // 避免登录页 / 在线主密码页残留在回退栈。
                                popUpTo(Screen.ModeSelect.route)
                            }
                        } catch (t: Throwable) {
                            val expired = t is ApiException.TokenExpired
                            val msg = if (createMode && !expired) {
                                "创建保险库失败：${t.message ?: t.javaClass.simpleName}"
                            } else if (expired) {
                                "登录已过期，请重新登录"
                            } else {
                                "主密码错误"
                            }
                            Toast.makeText(context, msg, Toast.LENGTH_LONG).show()
                            if (expired) {
                                // 登录已过期：清掉返回栈，回到登录页。
                                navController.navigate(Screen.OnlineLogin.route) {
                                    popUpTo(Screen.ModeSelect.route) { inclusive = true }
                                }
                            }
                        } finally {
                            loading = false
                        }
                    }
                },
            )
            Spacer(modifier = Modifier.height(SpaceMD))
            // 生物识别解锁仅在「已存在保险库」时才有意义（创建模式下尚无 vault 可指认）。
            // 在线指纹与主密码同构：Keystore 硬件密钥（要求指纹认证）加密 vaultKey，
            // 解锁时解出 vaultKey 直接进入在线会话（[OnlineBiometricUnlock]）。
            if (!createMode && OnlineBiometricUnlock.canOfferUnlock(context)) {
                PwdlockOutlinedButton(
                    text = "使用生物识别解锁",
                    onClick = {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return@PwdlockOutlinedButton
                        OnlineBiometricUnlock.unlock(
                            context = context,
                            onSuccess = {
                                navController.navigate(Screen.VaultHome.route) {
                                    popUpTo(Screen.ModeSelect.route)
                                }
                            },
                            onError = { msg ->
                                Toast.makeText(context, msg, Toast.LENGTH_LONG).show()
                            },
                            onCancel = {},
                            onAuthExpired = {
                                Toast.makeText(context, "登录已过期，请重新登录", Toast.LENGTH_LONG).show()
                                navController.navigate(Screen.OnlineLogin.route) {
                                    popUpTo(Screen.ModeSelect.route) { inclusive = true }
                                }
                            },
                        )
                    },
                )
            }

            Spacer(modifier = Modifier.height(SpaceXL))
            Text(
                text = "连续 5 次失败后需等待 30 秒冷却。",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            if (hasLogin) {
                Spacer(modifier = Modifier.height(SpaceXL))
                // 退出当前在线登录：清账户态与内存密钥，并直接跳登录页（清空回退栈）。
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable(onClick = {
                            VaultSession.logoutOnline(context)
                            navController.navigate(Screen.OnlineLogin.route) {
                                popUpTo(Screen.ModeSelect.route) { inclusive = true }
                                launchSingleTop = true
                            }
                        }),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        imageVector = Icons.Filled.Logout,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.error,
                        modifier = Modifier.size(16.dp),
                    )
                    Spacer(modifier = Modifier.padding(start = SpaceSM))
                    Text(
                        text = "退出当前登录",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            }

            Spacer(modifier = Modifier.height(SpaceXL))
            // 切换到本地模式：与设置页行为一致——按本机是否已有本地库跳对应首屏。
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(onClick = {
                        AppModePrefs.setLastMode(context, "local")
                        val localRoute =
                            if (VaultSession.hasVault(context)) Screen.Unlock.route else "create_master_password"
                        navController.navigate(localRoute) {
                            popUpTo(Screen.ModeSelect.route) { inclusive = true }
                            launchSingleTop = true
                        }
                    }),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    imageVector = Icons.Filled.CloudOff,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(16.dp),
                )
                Spacer(modifier = Modifier.padding(start = SpaceSM))
                Text(
                    text = "切换到本地模式",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
        }
        if (loading) LoadingOverlay(if (createMode) "创建中…" else "解密中…")
    }
}
