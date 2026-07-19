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
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import android.widget.Toast
import androidx.compose.ui.platform.LocalContext
import com.pwdlock.android.data.AppModePrefs
import com.pwdlock.android.data.vault.VaultSession
import com.pwdlock.android.navigation.Screen
import com.pwdlock.android.ui.components.LoadingOverlay
import com.pwdlock.android.ui.components.PasswordField
import com.pwdlock.android.ui.components.PwdlockButton
import com.pwdlock.android.ui.components.PwdlockTextField
import com.pwdlock.android.ui.components.PwdlockTopBar
import com.pwdlock.android.ui.theme.PwdlockColors
import com.pwdlock.android.ui.theme.RadiusLG
import com.pwdlock.android.ui.theme.ScreenHMargin
import com.pwdlock.android.ui.theme.SpaceLG
import com.pwdlock.android.ui.theme.SpaceMD
import com.pwdlock.android.ui.theme.SpaceSM
import com.pwdlock.android.ui.theme.SpaceXL
import com.pwdlock.android.ui.theme.SpaceXXL
import kotlinx.coroutines.launch

@Composable
fun OnlineLoginScreen(navController: NavHostController) {
    var account by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    Scaffold(
        topBar = { PwdlockTopBar(title = "登录", onBack = { navController.popBackStack() }) },
    ) { inner ->
        Box(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(inner)
                .background(MaterialTheme.colorScheme.background)
                .padding(horizontal = ScreenHMargin, vertical = SpaceXL),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Box(
                modifier = Modifier
                    .size(72.dp)
                    .clip(RoundedCornerShape(RadiusLG))
                    .background(PwdlockColors.BrandContainer),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Filled.Cloud,
                    contentDescription = null,
                    tint = PwdlockColors.Brand,
                    modifier = Modifier.size(38.dp),
                )
            }

            Spacer(modifier = Modifier.height(SpaceXL))
            Text(
                text = "登录在线账户",
                style = MaterialTheme.typography.titleLarge,
                color = MaterialTheme.colorScheme.onBackground,
            )
            Text(
                text = "登录后输入主密码即可解密云端保险库",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Spacer(modifier = Modifier.height(SpaceXXL))
            PwdlockTextField(
                label = "账号 / 邮箱",
                value = account,
                onValueChange = { account = it },
                keyboardType = KeyboardType.Email,
            )
            Spacer(modifier = Modifier.height(SpaceLG))
            PasswordField(
                label = "密码",
                value = password,
                onValueChange = { password = it },
            )

            Spacer(modifier = Modifier.height(SpaceXL))
            PwdlockButton(
                text = "登录",
                enabled = !loading,
                onClick = {
                    scope.launch {
                        loading = true
                        try {
                            VaultSession.loginOnline(context, account.trim(), password)
                            loading = false
                            AppModePrefs.setLastMode(context, "online")
                            navController.navigate(Screen.OnlineMasterPassword.route) {
                                // 与本地解锁对齐：进入在线主密码页后清掉 ModeSelect 以下的历史，
                                // 避免登录页残留在回退栈（返回键不会落回登录页）。
                                popUpTo(Screen.ModeSelect.route)
                            }
                        } catch (e: Exception) {
                            loading = false
                            val msg = if (e is com.pwdlock.android.data.network.ApiException.TokenExpired) {
                                "账号或密码错误"
                            } else {
                                "登录失败：${e.message ?: e.javaClass.simpleName}"
                            }
                            Toast.makeText(context, msg, Toast.LENGTH_LONG).show()
                        }
                    }
                },
            )
            Spacer(modifier = Modifier.height(SpaceLG))
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(onClick = { navController.navigate(Screen.OnlineRegister.route) }),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "还没有账号？",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(modifier = Modifier.padding(start = SpaceSM))
                Text(
                    text = "注册",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.primary,
                )
            }

            if (loading) LoadingOverlay("登录中…")
        }
        }
    }
}
