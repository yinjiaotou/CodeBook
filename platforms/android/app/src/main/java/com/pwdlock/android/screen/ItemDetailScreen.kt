package com.pwdlock.android.screen

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.navigation.NavBackStackEntry
import androidx.navigation.NavHostController
import android.util.Log
import com.pwdlock.android.data.vault.VaultSession
import com.pwdlock.android.data.model.toVaultItem
import com.pwdlock.android.navigation.Screen
import com.pwdlock.android.ui.components.DetailRow
import com.pwdlock.android.ui.components.InfoRow
import com.pwdlock.android.ui.components.ItemAvatar
import com.pwdlock.android.ui.components.PwdlockTopBar
import com.pwdlock.android.ui.theme.PwdlockColors
import com.pwdlock.android.ui.theme.RadiusMD
import com.pwdlock.android.ui.theme.ScreenHMargin
import com.pwdlock.android.ui.theme.SpaceLG
import com.pwdlock.android.ui.theme.SpaceMD
import com.pwdlock.android.ui.theme.SpaceXL
import com.pwdlock.android.util.ClipboardUtil

@Composable
fun ItemDetailScreen(navController: NavHostController, backStackEntry: NavBackStackEntry) {
    val context = LocalContext.current
    val itemId = backStackEntry.arguments?.getString("itemId")
    val record = itemId?.let { VaultSession.getRecord(it) }
    val snackbar = remember { SnackbarHostState() }
    var showDelete by remember { mutableStateOf(false) }

    if (record == null) {
        LaunchedEffect(Unit) { navController.popBackStack() }
        return
    }
    val item = record.toVaultItem()

    Scaffold(
        topBar = {
            PwdlockTopBar(
                title = item.title,
                onBack = { navController.popBackStack() },
                actions = {
                    IconButton(onClick = { navController.navigate("item_edit?itemId=${record.id}") }) {
                        Icon(Icons.Filled.Edit, contentDescription = "编辑")
                    }
                    IconButton(onClick = { showDelete = true }) {
                        Icon(Icons.Filled.Delete, contentDescription = "删除")
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbar) },
    ) { inner ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(inner)
                .padding(vertical = SpaceLG),
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = ScreenHMargin),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                ItemAvatar(title = item.title, size = 56.dp)
                Column(modifier = Modifier.padding(start = SpaceLG)) {
                    Text(
                        text = item.title,
                        style = MaterialTheme.typography.titleLarge,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                    Surface(
                        shape = RoundedCornerShape(999.dp),
                        color = PwdlockColors.BrandContainer,
                    ) {
                        Text(
                            text = item.category,
                            style = MaterialTheme.typography.labelMedium,
                            color = PwdlockColors.OnBrandContainer,
                            modifier = Modifier.padding(horizontal = SpaceMD, vertical = 2.dp),
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(SpaceXL))
            Surface(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = ScreenHMargin)
                    .clip(RoundedCornerShape(RadiusMD)),
                color = MaterialTheme.colorScheme.surface,
                shadowElevation = 1.dp,
            ) {
                Column {
                    DetailRow(
                        label = "用户名",
                        value = item.username,
                        onCopy = { ClipboardUtil.copy(context, item.username) },
                    )
                    DetailRow(
                        label = "密码",
                        value = item.password,
                        revealable = true,
                        onCopy = { ClipboardUtil.copy(context, item.password) },
                    )
                    DetailRow(
                        label = "网址",
                        value = item.url,
                        onCopy = { ClipboardUtil.copy(context, item.url) },
                    )
                    if (item.note.isNotBlank()) {
                        DetailRow(
                            label = "备注",
                            value = item.note,
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(SpaceLG))
            InfoRow(
                label = "更新时间",
                value = item.updatedAt,
                modifier = Modifier.padding(horizontal = ScreenHMargin),
            )
        }
    }

    if (showDelete) {
        AlertDialog(
            onDismissRequest = { showDelete = false },
            title = { Text("删除登录项") },
            text = { Text("确定要删除「${item.title}」吗？此操作不可撤销。") },
            confirmButton = {
                TextButton(
                    onClick = {
                        // 自动锁定可能已在弹窗期间清空 vaultKey；主线程同步调用 delete 抛异常会直接闪退。
                        if (VaultSession.isUnlocked()) {
                            try {
                                VaultSession.delete(context, record.id)
                                navController.popBackStack()
                            } catch (e: Exception) {
                                Log.e("ItemDetail", "delete failed", e)
                                navController.popBackStack()
                            }
                        } else {
                            showDelete = false
                            navController.navigate(Screen.Unlock.route) { popUpTo(Screen.ModeSelect.route) }
                        }
                    },
                ) { Text("删除") }
            },
            dismissButton = {
                TextButton(onClick = { showDelete = false }) { Text("取消") }
            },
        )
    }
}
