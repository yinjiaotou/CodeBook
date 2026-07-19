package com.pwdlock.android.screen

import androidx.compose.foundation.BorderStroke
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
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.CloudOff
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import com.pwdlock.android.data.AppModePrefs
import com.pwdlock.android.data.vault.VaultSession
import com.pwdlock.android.navigation.Screen
import java.io.File
import com.pwdlock.android.ui.theme.PwdlockColors
import com.pwdlock.android.ui.theme.RadiusLG
import com.pwdlock.android.ui.theme.SpaceLG
import com.pwdlock.android.ui.theme.SpaceMD
import com.pwdlock.android.ui.theme.SpaceSM
import com.pwdlock.android.ui.theme.SpaceXL
import com.pwdlock.android.ui.theme.SpaceXXL
import com.pwdlock.android.ui.theme.SpaceXXXL

@Composable
fun ModeSelectScreen(navController: NavHostController) {
    val context = LocalContext.current
    val crashTextState = remember { mutableStateOf<String?>(null) }

    // 启动不再自动分流：每次进入应用都停留在模式选择页，由用户显式选择「在线 / 本地」。
    // 仅当上次发生过崩溃时，展示堆栈便于反馈「直接闪退」类问题。
    LaunchedEffect(Unit) {
        val crashFile = File(context.filesDir, "crash.log")
        if (crashFile.exists()) {
            crashTextState.value = crashFile.readText().take(6000)
            crashFile.delete()
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .padding(horizontal = SpaceXXL, vertical = SpaceXXXL),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Box(
            modifier = Modifier
                .size(88.dp)
                .clip(RoundedCornerShape(26.dp))
                .background(PwdlockColors.Brand),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = Icons.Filled.Shield,
                contentDescription = null,
                tint = PwdlockColors.BrandContainer,
                modifier = Modifier.size(48.dp),
            )
        }

        Spacer(modifier = Modifier.height(SpaceXL))
        Text(
            text = "Pwdlock",
            style = MaterialTheme.typography.displaySmall,
            color = MaterialTheme.colorScheme.onBackground,
        )
        Spacer(modifier = Modifier.height(SpaceSM))
        Text(
            text = "请选择运行模式",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        Spacer(modifier = Modifier.height(SpaceXXL))
        ModeCard(
            icon = Icons.Filled.CloudOff,
            iconTint = PwdlockColors.Success,
            iconContainer = PwdlockColors.SuccessContainer,
            title = "本地模式",
            desc = "数据仅存于本机，端侧全加密，无需账号，离线可用。",
            onClick = {
                AppModePrefs.setLastMode(context, "local")
                if (VaultSession.hasVault(context)) {
                    navController.navigate(Screen.Unlock.route)
                } else {
                    navController.navigate("create_master_password")
                }
            },
        )
        Spacer(modifier = Modifier.height(SpaceMD))
        ModeCard(
            icon = Icons.Filled.Cloud,
            iconTint = PwdlockColors.Brand,
            iconContainer = PwdlockColors.BrandContainer,
            title = "在线模式",
            desc = "登录账号后，加密数据同步至云端服务器，多端可用。",
            onClick = {
                AppModePrefs.setLastMode(context, "online")
                navController.navigate(Screen.OnlineLogin.route)
            },
        )

        Spacer(modifier = Modifier.height(SpaceLG))
        Text(
            text = "两种模式随时可在「设置」中切换。在线模式同样采用端侧加密，服务器无法读取你的明文。",
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
    }

    if (crashTextState.value != null) {
        AlertDialog(
            onDismissRequest = { crashTextState.value = null },
            title = { Text("上次运行崩溃已捕获") },
            text = {
                Column(modifier = Modifier.verticalScroll(rememberScrollState())) {
                    Text(
                        text = crashTextState.value!!,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            },
            confirmButton = {
                TextButton(onClick = { crashTextState.value = null }) { Text("我知道了") }
            },
        )
    }
}

@Composable
private fun ModeCard(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    iconTint: Color,
    iconContainer: Color,
    title: String,
    desc: String,
    onClick: () -> Unit,
) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(RadiusLG),
        color = MaterialTheme.colorScheme.surface,
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
        tonalElevation = 0.dp,
        shadowElevation = 0.dp,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(SpaceLG),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .size(48.dp)
                    .clip(RoundedCornerShape(RadiusLG))
                    .background(iconContainer),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    tint = iconTint,
                    modifier = Modifier.size(26.dp),
                )
            }
            Column(
                modifier = Modifier
                    .weight(1f)
                    .padding(start = SpaceLG),
                verticalArrangement = Arrangement.Center,
            ) {
                Text(
                    text = title,
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Spacer(modifier = Modifier.height(SpaceSM))
                Text(
                    text = desc,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Icon(
                imageVector = Icons.Filled.ChevronRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(22.dp),
            )
        }
    }
}
