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
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import com.pwdlock.android.ui.components.AccentNote
import com.pwdlock.android.ui.components.NoteTone
import com.pwdlock.android.ui.components.PwdlockTopBar
import com.pwdlock.android.ui.theme.PwdlockColors
import com.pwdlock.android.ui.theme.RadiusLG
import com.pwdlock.android.ui.theme.ScreenHMargin
import com.pwdlock.android.ui.theme.SpaceLG
import com.pwdlock.android.ui.theme.SpaceMD
import com.pwdlock.android.ui.theme.SpaceXL
import com.pwdlock.android.ui.theme.SpaceSM

@Composable
fun AboutScreen(navController: NavHostController) {
    Scaffold(
        topBar = { PwdlockTopBar(title = "关于", onBack = { navController.popBackStack() }) },
    ) { inner ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(inner)
                .padding(horizontal = ScreenHMargin, vertical = SpaceXL),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Box(
                modifier = Modifier
                    .size(72.dp)
                    .clip(RoundedCornerShape(RadiusLG))
                    .background(PwdlockColors.Brand),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Filled.Shield,
                    contentDescription = null,
                    tint = PwdlockColors.BrandContainer,
                    modifier = Modifier.size(40.dp),
                )
            }
            Spacer(modifier = Modifier.height(SpaceLG))
            Text("Pwdlock", style = MaterialTheme.typography.titleLarge, color = MaterialTheme.colorScheme.onBackground)
            Text("离线本地密码管理器", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)

            Spacer(modifier = Modifier.height(SpaceXL))
            InfoCard(
                label = "应用版本",
                value = "1.0.0 (build 1)",
            )
            InfoCard(
                label = "文件协议",
                value = "pwdlock v1",
            )
            InfoCard(
                label = "加密方案",
                value = "Argon2id + AES-256-GCM",
            )

            Spacer(modifier = Modifier.height(SpaceLG))
            AccentNote(
                icon = Icons.Filled.Shield,
                tone = NoteTone.Info,
                title = "隐私声明",
                text = "本应用不登录账号、不上传任何用户数据、不提供云端同步。所有数据仅保存在你的设备本地。",
            )

            Spacer(modifier = Modifier.height(SpaceMD))
            AccentNote(
                icon = Icons.Filled.Shield,
                tone = NoteTone.Warning,
                title = "安全边界",
                text = "我们不承诺防护已解锁设备上的恶意软件、键盘记录器或系统级录屏。加密与强主密码才是核心保障。",
            )
        }
    }
}

@Composable
private fun InfoCard(label: String, value: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = SpaceSM)
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .padding(SpaceLG),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurface)
    }
}
