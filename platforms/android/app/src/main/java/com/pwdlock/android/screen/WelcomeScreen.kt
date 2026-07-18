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
import androidx.compose.material.icons.filled.CloudOff
import androidx.compose.material.icons.filled.Fingerprint
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import com.pwdlock.android.data.vault.VaultSession
import com.pwdlock.android.navigation.Screen
import com.pwdlock.android.ui.components.PwdlockButton
import com.pwdlock.android.ui.theme.PwdlockColors
import com.pwdlock.android.ui.theme.RadiusLG
import com.pwdlock.android.ui.theme.SpaceLG
import com.pwdlock.android.ui.theme.SpaceMD
import com.pwdlock.android.ui.theme.SpaceXL
import com.pwdlock.android.ui.theme.SpaceXXL
import com.pwdlock.android.ui.theme.SpaceXXXL
import com.pwdlock.android.ui.theme.SpaceSM
import androidx.compose.ui.platform.LocalContext

@Composable
fun WelcomeScreen(navController: NavHostController) {
    val context = LocalContext.current
    val hasVault = VaultSession.hasVault(context)

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
            text = "离线密码库 · 端侧全加密",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        Spacer(modifier = Modifier.height(SpaceXXL))
        FeatureRow(
            icon = Icons.Filled.CloudOff,
            title = "无服务端",
            desc = "数据只留在你的设备，不登录、不上传",
        )
        Spacer(modifier = Modifier.height(SpaceMD))
        FeatureRow(
            icon = Icons.Filled.Shield,
            title = "信封加密",
            desc = "Vault Key + Argon2id + AES-256-GCM",
        )
        Spacer(modifier = Modifier.height(SpaceMD))
        FeatureRow(
            icon = Icons.Filled.Fingerprint,
            title = "可迁移",
            desc = "跨端加密 .pwdlock 文件自由备份",
        )

        Spacer(modifier = Modifier.height(SpaceXXL))
        if (hasVault) {
            PwdlockButton(
                text = "解锁保险库",
                onClick = { navController.navigate(Screen.Unlock.route) },
            )
        } else {
            PwdlockButton(
                text = "创建主密码",
                onClick = { navController.navigate("create_master_password") },
            )
        }
        Spacer(modifier = Modifier.height(SpaceMD))
    }
}

@Composable
private fun FeatureRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    desc: String,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(RoundedCornerShape(RadiusLG))
                .background(PwdlockColors.BrandContainer),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = PwdlockColors.Brand,
                modifier = Modifier.size(22.dp),
            )
        }
        Column(
            modifier = Modifier
                .weight(1f)
                .padding(start = SpaceLG),
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                text = desc,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Start,
            )
        }
    }
}
