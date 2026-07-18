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
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Person
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
import android.widget.Toast
import androidx.navigation.NavHostController
import com.pwdlock.android.data.network.ApiException
import com.pwdlock.android.data.online.OnlineAccountStore
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

@Composable
fun OnlineMasterPasswordScreen(navController: NavHostController) {
    var password by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val loggedInAccount = OnlineAccountStore.loginName(context) ?: ""

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
                text = "输入主密码以解密云端保险库",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )

            Spacer(modifier = Modifier.height(SpaceMD))
            // 已登录账号提示
            if (loggedInAccount.isNotBlank()) {
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(RadiusPill))
                        .background(PwdlockColors.BrandContainer)
                        .padding(horizontal = SpaceLG, vertical = SpaceSM),
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            imageVector = Icons.Filled.Person,
                            contentDescription = null,
                            tint = PwdlockColors.Brand,
                            modifier = Modifier.size(16.dp),
                        )
                        Spacer(modifier = Modifier.padding(start = SpaceSM))
                        Text(
                            text = loggedInAccount,
                            style = MaterialTheme.typography.bodyMedium,
                            color = PwdlockColors.OnBrandContainer,
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(SpaceXXL))
            PasswordField(
                label = "主密码",
                value = password,
                onValueChange = { password = it },
            )

            Spacer(modifier = Modifier.height(SpaceLG))
            PwdlockButton(
                text = "解锁",
                enabled = !loading,
                onClick = {
                    scope.launch {
                        loading = true
                        try {
                            VaultSession.unlockOnline(context, password)
                            loading = false
                            navController.navigate(Screen.VaultHome.route)
                        } catch (e: Exception) {
                            loading = false
                            val msg = if (e is ApiException.TokenExpired) {
                                "登录已过期，请重新登录"
                            } else {
                                "主密码错误"
                            }
                            Toast.makeText(context, msg, Toast.LENGTH_LONG).show()
                        }
                    }
                },
            )
            Spacer(modifier = Modifier.height(SpaceMD))
            PwdlockOutlinedButton(
                text = "使用生物识别解锁",
                onClick = { /* 占位：调用系统生物识别 */ },
            )

            Spacer(modifier = Modifier.height(SpaceXL))
            Text(
                text = "连续 5 次失败后需等待 30 秒冷却。",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        if (loading) LoadingOverlay("解密中…")
    }
}
