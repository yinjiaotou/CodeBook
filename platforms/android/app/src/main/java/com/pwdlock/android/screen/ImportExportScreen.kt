package com.pwdlock.android.screen

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.FileDownload
import androidx.compose.material.icons.filled.FileUpload
import androidx.compose.material.icons.filled.Info
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
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
import com.pwdlock.android.ui.components.PwdlockTopBar
import com.pwdlock.android.ui.theme.PwdlockColors
import com.pwdlock.android.ui.theme.RadiusLG
import com.pwdlock.android.ui.theme.RadiusMD
import com.pwdlock.android.ui.theme.ScreenHMargin
import com.pwdlock.android.ui.theme.SpaceLG
import com.pwdlock.android.ui.theme.SpaceMD
import com.pwdlock.android.ui.theme.SpaceXL
import com.pwdlock.android.ui.theme.SpaceSM

@Composable
fun ImportExportScreen(navController: NavHostController) {
    val context = LocalContext.current

    // 进入导入/导出页即开启「导入流程豁免」：覆盖选文件与在此页停留的全程，
    // 避免前台闲置锁定或切后台锁定在导入前清空 vaultKey，导致后续 mergeImport 抛「vault is locked」。
    DisposableEffect(Unit) {
        VaultSession.importFlowActive = true
        onDispose { VaultSession.importFlowActive = false }
    }

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        try {
            context.contentResolver.openInputStream(uri)?.use { it.readBytes() }?.let { bytes ->
                VaultSession.setPendingImport(bytes)
                navController.navigate(Screen.ImportPreview.route)
            }
        } catch (_: Exception) {
            // 读取失败：忽略，停留在当前页
        }
    }

    Scaffold(
        topBar = { PwdlockTopBar(title = "导入 / 导出", onBack = { navController.popBackStack() }) },
    ) { inner ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(inner)
                .padding(horizontal = ScreenHMargin, vertical = SpaceXL),
            verticalArrangement = Arrangement.spacedBy(SpaceLG),
        ) {
            ActionCard(
                icon = Icons.Filled.FileDownload,
                tint = PwdlockColors.Brand,
                title = "导出保险库",
                desc = "生成加密的 .pwdlock 文件，用于备份或迁移到其他设备。",
                onClick = { navController.navigate(Screen.ExportPassword.route) },
            )
            ActionCard(
                icon = Icons.Filled.FileUpload,
                tint = PwdlockColors.Success,
                title = "导入保险库",
                desc = "从 .pwdlock 文件恢复或合并数据，冲突会被保留待你裁决。",
                onClick = { picker.launch("*/*") },
            )

            AccentNote(
                icon = Icons.Filled.Info,
                tone = NoteTone.Info,
                title = "端到端加密",
                text = "导出文件使用独立的导出密码加密（AES-256-GCM + Argon2id），即使文件被他人获取也无法解密。",
            )

            Spacer(modifier = Modifier.height(SpaceMD))
        }
    }
}

@Composable
private fun ActionCard(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    tint: androidx.compose.ui.graphics.Color,
    title: String,
    desc: String,
    onClick: () -> Unit,
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(RadiusMD))
            .background(MaterialTheme.colorScheme.surface)
            .clickable(onClick = onClick)
            .padding(SpaceLG),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = Modifier
                    .size(44.dp)
                    .clip(RoundedCornerShape(RadiusLG))
                    .background(tint.copy(alpha = 0.12f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(imageVector = icon, contentDescription = null, tint = tint, modifier = Modifier.size(24.dp))
            }
            Column(modifier = Modifier.weight(1f).padding(start = SpaceLG)) {
                Text(title, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurface)
                Spacer(modifier = Modifier.height(SpaceSM))
                Text(desc, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Icon(
                imageVector = Icons.AutoMirrored.Filled.ArrowForward,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
