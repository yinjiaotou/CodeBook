package com.pwdlock.android.screen

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.navigation.NavBackStackEntry
import androidx.navigation.NavHostController
import android.util.Log
import com.pwdlock.android.data.vault.VaultRecordDraft
import com.pwdlock.android.data.vault.VaultSession
import com.pwdlock.android.navigation.Screen
import com.pwdlock.android.ui.components.PasswordField
import com.pwdlock.android.ui.components.PwdlockButton
import com.pwdlock.android.ui.components.PwdlockOutlinedButton
import com.pwdlock.android.ui.components.PwdlockTextField
import com.pwdlock.android.ui.components.PwdlockTopBar
import com.pwdlock.android.ui.theme.RadiusMD
import com.pwdlock.android.ui.theme.ScreenHMargin
import com.pwdlock.android.ui.theme.SpaceLG
import com.pwdlock.android.ui.theme.SpaceSM
import com.pwdlock.android.ui.theme.SpaceXL
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.platform.LocalContext
import androidx.compose.runtime.rememberCoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private val GenChars = "ABCDEFGHJKMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789!@#\$%^&*"

private fun quickPassword(len: Int = 16): String =
    (1..len).joinToString("") { GenChars.random().toString() }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ItemEditScreen(navController: NavHostController, backStackEntry: NavBackStackEntry) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val itemId = backStackEntry.arguments?.getString("itemId")
    val existing = itemId?.let { VaultSession.getRecord(it) }

    // 使用 rememberSaveable：导航到密码生成器等子页再返回时，已填内容保留（不会被重建清空）。
    var title by rememberSaveable { mutableStateOf(existing?.title ?: "") }
    var username by rememberSaveable { mutableStateOf(existing?.username ?: "") }
    var password by rememberSaveable { mutableStateOf(existing?.password ?: "") }
    var url by rememberSaveable { mutableStateOf(existing?.url ?: "") }
    var note by rememberSaveable { mutableStateOf(existing?.note ?: "") }
    // 分类默认空：不预置任何默认值，由用户手输或点选已有分类。
    var category by rememberSaveable { mutableStateOf(existing?.category ?: "") }

    // 现有分类 = 保险库中已有记录的分类（去重、去空），供点选。
    val items by VaultSession.items.collectAsState()
    val existingCategories = remember(items) {
        items.map { it.category }
            .map { it.trim() }
            .filter { it.isNotBlank() }
            .distinct()
    }

    val canSave = title.isNotBlank()

    Scaffold(
        topBar = {
            PwdlockTopBar(title = if (existing != null) "编辑登录项" else "新增登录项", onBack = { navController.popBackStack() })
        },
    ) { inner ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(inner)
                .verticalScroll(rememberScrollState())
                .imePadding()
                .padding(horizontal = ScreenHMargin, vertical = SpaceXL),
            verticalArrangement = Arrangement.spacedBy(SpaceLG),
        ) {
            PwdlockTextField(label = "标题", value = title, onValueChange = { title = it })
            PwdlockTextField(label = "用户名 / 邮箱", value = username, onValueChange = { username = it })

            // 密码 + 生成
            Column(verticalArrangement = Arrangement.spacedBy(SpaceSM)) {
                PasswordField(
                    label = "密码",
                    value = password,
                    onValueChange = { password = it },
                    trailing = {
                        IconButton(onClick = { password = quickPassword() }) {
                            Icon(Icons.Filled.Refresh, contentDescription = "生成密码")
                        }
                    },
                )
                PwdlockOutlinedButton(
                    text = "打开密码生成器",
                    onClick = { navController.navigate(Screen.PasswordGenerator.route) },
                )
            }

            PwdlockTextField(label = "网址", value = url, onValueChange = { url = it }, keyboardType = KeyboardType.Uri)

            // 分类：可手输新分类，也可点选已有分类（横向滚动标签，始终可点）。
            Column(verticalArrangement = Arrangement.spacedBy(SpaceSM)) {
                PwdlockTextField(label = "分类", value = category, onValueChange = { category = it })
                if (existingCategories.isNotEmpty()) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(SpaceSM),
                    ) {
                        existingCategories.forEach { cat ->
                            FilterChip(
                                selected = category == cat,
                                onClick = { category = cat },
                                label = { Text(cat) },
                            )
                        }
                    }
                }
            }

            // 备注（多行）
            OutlinedTextField(
                value = note,
                onValueChange = { note = it },
                label = { Text("备注") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = false,
                minLines = 3,
                shape = RoundedCornerShape(RadiusMD),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = MaterialTheme.colorScheme.primary,
                    unfocusedBorderColor = MaterialTheme.colorScheme.outline,
                ),
            )

            Spacer(modifier = Modifier.height(SpaceLG))
            PwdlockButton(
                text = "保存",
                enabled = canSave,
                onClick = {
                    // 自动锁定（切后台 / 闲置超时）可能已在编辑期间清空 vaultKey，
                    // 写入前先确认解锁态，否则 upsert 抛异常会在 IO 协程中未被捕获而闪退。
                    if (VaultSession.isUnlocked()) {
                        scope.launch(Dispatchers.IO) {
                            try {
                                VaultSession.upsert(
                                    context,
                                    VaultRecordDraft(
                                        id = existing?.id,
                                        title = title,
                                        username = username,
                                        password = password,
                                        url = url,
                                        category = category,
                                        note = note,
                                    ),
                                )
                                withContext(Dispatchers.Main) { navController.popBackStack() }
                            } catch (e: Exception) {
                                Log.e("ItemEdit", "upsert failed", e)
                                withContext(Dispatchers.Main) { navController.popBackStack() }
                            }
                        }
                    } else {
                        navController.navigate(Screen.Unlock.route) { popUpTo(Screen.ModeSelect.route) }
                    }
                },
            )
        }
    }
}
