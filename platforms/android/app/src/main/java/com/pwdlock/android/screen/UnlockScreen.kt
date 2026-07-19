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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.Fingerprint
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import android.os.Build
import android.util.Log
import android.widget.Toast
import androidx.navigation.NavHostController
import com.pwdlock.android.data.vault.BiometricUnlock
import com.pwdlock.android.data.AppModePrefs
import com.pwdlock.android.data.online.OnlineAccountStore
import com.pwdlock.android.data.vault.VaultSession
import com.pwdlock.android.navigation.Screen
import com.pwdlock.android.ui.components.LoadingOverlay
import com.pwdlock.android.ui.components.PasswordField
import com.pwdlock.android.ui.components.PwdlockButton
import com.pwdlock.android.ui.components.PwdlockOutlinedButton
import com.pwdlock.android.ui.theme.PwdlockColors
import com.pwdlock.android.ui.theme.RadiusLG
import com.pwdlock.android.ui.theme.ScreenHMargin
import com.pwdlock.android.ui.theme.SpaceLG
import com.pwdlock.android.ui.theme.SpaceXL
import com.pwdlock.android.ui.theme.SpaceXXL
import com.pwdlock.android.ui.theme.SpaceMD
import com.pwdlock.android.ui.theme.SpaceSM
import androidx.compose.runtime.rememberCoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun UnlockScreen(navController: NavHostController) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var password by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var importing by remember { mutableStateOf(false) }
    val canBiometric = remember { BiometricUnlock.canOfferUnlock(context) }

    fun toVaultHome() {
        AppModePrefs.setLastMode(context, "local")
        navController.navigate(Screen.VaultHome.route) {
            popUpTo(Screen.ModeSelect.route)
        }
    }

    /** 解锁成功后：若有「确认导入」时暂存的待续导入，自动执行合并并直接进密码库（不锁定），否则直接进密码库。 */
    fun afterUnlock() {
        val pending = VaultSession.pendingMergePayload
        if (pending != null) {
            importing = true
            scope.launch(Dispatchers.IO) {
                try {
                    val result = VaultSession.mergeImport(context, pending)
                    VaultSession.clearPendingImport()
                    VaultSession.pendingMergePayload = null
                    withContext(Dispatchers.Main) {
                        val msg = if (result.conflicts > 0) {
                            "导入成功，存在 ${result.conflicts} 个冲突待处理"
                        } else {
                            "导入成功"
                        }
                        Toast.makeText(context, msg, Toast.LENGTH_SHORT).show()
                    }
                    delay(1000)
                    withContext(Dispatchers.Main) {
                        importing = false
                        if (result.conflicts > 0) {
                            navController.navigate(Screen.VaultHome.route) { popUpTo(Screen.ModeSelect.route) }
                            navController.navigate(Screen.ConflictCenter.route)
                        } else {
                            toVaultHome()
                        }
                    }
                } catch (e: Exception) {
                    Log.e("Unlock", "pending mergeImport failed", e)
                    VaultSession.pendingMergePayload = null
                    VaultSession.clearPendingImport()
                    withContext(Dispatchers.Main) {
                        importing = false
                        Toast.makeText(context, "导入失败", Toast.LENGTH_SHORT).show()
                        toVaultHome()
                    }
                }
            }
        } else {
            toVaultHome()
        }
    }

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
        }

        Spacer(modifier = Modifier.height(SpaceXL))
        Text(
            text = "欢迎回来",
            style = MaterialTheme.typography.titleLarge,
            color = MaterialTheme.colorScheme.onBackground,
        )
        Text(
            text = "输入主密码以解锁密码库",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )

        Spacer(modifier = Modifier.height(SpaceXXL))
        PasswordField(
            label = "主密码",
            value = password,
            onValueChange = { password = it; error = null },
        )

        if (error != null) {
            Spacer(modifier = Modifier.height(SpaceMD))
            Text(
                text = error!!,
                style = MaterialTheme.typography.bodyMedium,
                color = PwdlockColors.Danger,
                textAlign = TextAlign.Center,
            )
        }

        Spacer(modifier = Modifier.height(SpaceLG))
        PwdlockButton(
            text = "解锁",
            enabled = !busy && !importing,
            onClick = {
                busy = true
                error = null
                scope.launch(Dispatchers.IO) {
                    val ok = VaultSession.unlock(context, password)
                    withContext(Dispatchers.Main) {
                        if (ok) {
                            afterUnlock()
                        } else {
                            error = "主密码错误，请重试。"
                            busy = false
                        }
                    }
                }
            },
        )
        if (canBiometric) {
            Spacer(modifier = Modifier.height(SpaceMD))
            PwdlockOutlinedButton(
                text = "使用指纹解锁",
                onClick = {
                    error = null
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        BiometricUnlock.unlock(
                            context = context,
                            onSuccess = { afterUnlock() },
                            onError = { msg -> error = msg },
                            onCancel = { },
                        )
                    }
                },
            )
        }

        Spacer(modifier = Modifier.height(SpaceXL))
        Text(
            text = "连续 5 次失败后需等待 30 秒冷却。",
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        Spacer(modifier = Modifier.height(SpaceMD))
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(onClick = {
                    AppModePrefs.setLastMode(context, "online")
                    // 按本机是否仍存有在线登录信息（token）决定直接进入在线主密码页
                    // （免重登）还是先到登录页。
                    val onlineRoute =
                        if (OnlineAccountStore.hasToken(context)) Screen.OnlineMasterPassword.route else Screen.OnlineLogin.route
                    navController.navigate(onlineRoute) {
                        popUpTo(Screen.ModeSelect.route) { inclusive = true }
                        launchSingleTop = true
                    }
                }),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = Icons.Filled.Cloud,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(16.dp),
            )
            Spacer(modifier = Modifier.padding(start = SpaceSM))
            Text(
                text = "切换到在线模式",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.primary,
            )
        }
        }

        if (importing) {
            LoadingOverlay(text = "正在导入…")
        }
    }
}
