package com.pwdlock.android.screen

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import android.util.Log
import com.pwdlock.android.data.model.LocalConflict
import com.pwdlock.android.data.model.PwdlockRecord
import com.pwdlock.android.data.model.formatDate
import com.pwdlock.android.data.vault.VaultSession
import com.pwdlock.android.navigation.Screen
import com.pwdlock.android.ui.components.PwdlockButton
import com.pwdlock.android.ui.components.PwdlockOutlinedButton
import com.pwdlock.android.ui.components.PwdlockTopBar
import com.pwdlock.android.ui.theme.PwdlockColors
import com.pwdlock.android.ui.theme.RadiusMD
import com.pwdlock.android.ui.theme.ScreenHMargin
import com.pwdlock.android.ui.theme.SpaceLG
import com.pwdlock.android.ui.theme.SpaceMD
import com.pwdlock.android.ui.theme.SpaceSM
import com.pwdlock.android.ui.theme.SpaceXL

@Composable
fun ConflictCenterScreen(navController: NavHostController) {
    val context = LocalContext.current
    val conflicts by VaultSession.conflicts.collectAsState()

    // 冲突裁决期间豁免自动锁定：vaultKey 保持在线，避免跳转到锁定界面。
    DisposableEffect(Unit) {
        VaultSession.importFlowActive = true
        onDispose { VaultSession.importFlowActive = false }
    }
    // 从导入流程进入且有冲突：全部裁决完成后直接进入密码库（不跳转锁定界面）。
    val initialHadConflicts = remember { conflicts.isNotEmpty() }
    LaunchedEffect(conflicts.isEmpty()) {
        if (initialHadConflicts && conflicts.isEmpty()) {
            navController.navigate(Screen.VaultHome.route) { popUpTo(Screen.ModeSelect.route) }
        }
    }

    Scaffold(
        topBar = { PwdlockTopBar(title = "冲突中心", onBack = { navController.popBackStack() }) },
    ) { inner ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(inner)
                .padding(horizontal = ScreenHMargin, vertical = SpaceXL),
        ) {
            if (conflicts.isEmpty()) {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = "暂无冲突。\n从外部 .pwdlock 导入相同 id 但内容不同的记录时会在此出现。",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            } else {
                Text(
                    text = "共 ${conflicts.size} 个冲突待处理。冲突不会被静默覆盖，请逐一裁决。",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(modifier = Modifier.height(SpaceLG))

                LazyColumn(
                    modifier = Modifier.fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(SpaceMD),
                ) {
                    items(conflicts, key = { it.id }) { conflict ->
                        ConflictItemCard(
                            conflict = conflict,
                            onKeepLocal = {
                                try {
                                    VaultSession.resolveKeepLocal(context, conflict.id)
                                } catch (e: Exception) {
                                    Log.e("ConflictCenter", "resolveKeepLocal failed", e)
                                }
                            },
                            onUseImported = {
                                try {
                                    VaultSession.resolveUseImported(context, conflict.id)
                                } catch (e: Exception) {
                                    Log.e("ConflictCenter", "resolveUseImported failed", e)
                                }
                            },
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ConflictItemCard(
    conflict: LocalConflict,
    onKeepLocal: () -> Unit,
    onUseImported: () -> Unit,
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(RadiusMD),
        color = MaterialTheme.colorScheme.surface,
        shadowElevation = 1.dp,
    ) {
        Column(modifier = Modifier.padding(SpaceLG)) {
            Text(
                text = conflict.title.ifBlank { "(无标题)" },
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Spacer(modifier = Modifier.height(SpaceMD))

            VariantBlock("本地版", PwdlockColors.Success, conflict.local)
            Spacer(modifier = Modifier.height(SpaceSM))
            VariantBlock("导入版", PwdlockColors.Warning, conflict.imported)

            Spacer(modifier = Modifier.height(SpaceMD))
            Row(horizontalArrangement = Arrangement.spacedBy(SpaceMD)) {
                Box(modifier = Modifier.weight(1f)) {
                    PwdlockOutlinedButton(text = "保留本地", onClick = onKeepLocal)
                }
                Box(modifier = Modifier.weight(1f)) {
                    PwdlockButton(text = "用导入替换", onClick = onUseImported)
                }
            }
        }
    }
}

@Composable
private fun VariantBlock(
    label: String,
    accent: androidx.compose.ui.graphics.Color,
    record: PwdlockRecord,
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(RadiusMD),
        color = MaterialTheme.colorScheme.surfaceVariant,
    ) {
        Column(modifier = Modifier.padding(SpaceMD)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = label,
                    style = MaterialTheme.typography.labelMedium,
                    color = accent,
                    modifier = Modifier.weight(1f),
                )
                Text(
                    text = "rev ${record.revision} · ${formatDate(record.updatedAtMs)}",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Spacer(modifier = Modifier.height(SpaceSM))
            FieldLine("账号", record.username)
            FieldLine("密码", if (record.password.isBlank()) "—" else "••••••••")
            if (record.url.isNotBlank()) FieldLine("网址", record.url)
            if (record.note.isNotBlank()) FieldLine("备注", record.note)
        }
    }
}

@Composable
private fun FieldLine(label: String, value: String) {
    Row(modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp)) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.width(56.dp),
        )
        Text(
            text = value.ifBlank { "—" },
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurface,
        )
    }
}
