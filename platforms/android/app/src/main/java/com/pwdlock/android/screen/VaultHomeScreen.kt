package com.pwdlock.android.screen

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import android.app.Activity
import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.platform.LocalContext
import androidx.navigation.NavHostController
import androidx.navigation.compose.currentBackStackEntryAsState
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import com.pwdlock.android.data.vault.VaultSession
import com.pwdlock.android.navigation.Screen
import com.pwdlock.android.ui.components.PwdlockSearchBar
import com.pwdlock.android.ui.components.PwdlockTopBar
import com.pwdlock.android.ui.components.VaultItemRow
import com.pwdlock.android.ui.theme.PwdlockColors
import com.pwdlock.android.ui.theme.RadiusMD
import com.pwdlock.android.ui.theme.ScreenHMargin
import com.pwdlock.android.ui.theme.SpaceLG
import com.pwdlock.android.ui.theme.SpaceMD
import com.pwdlock.android.ui.theme.SpaceSM

@Composable
fun VaultHomeScreen(navController: NavHostController) {
    val items by VaultSession.items.collectAsState()
    val context = LocalContext.current
    val activity = context as? Activity
    val scope = rememberCoroutineScope()
    var backPressedOnce by remember { mutableStateOf(false) }

    // 当前是否停留在密码库首页：是则拦截系统返回键，改为「再按一次退出」。
    // 在子页面（设置、详情、编辑）时该 Handler 禁用，返回键走默认出栈。
    val currentRoute = navController.currentBackStackEntryAsState().value?.destination?.route
    BackHandler(enabled = currentRoute == Screen.VaultHome.route) {
        if (backPressedOnce) {
            activity?.finish()
        } else {
            backPressedOnce = true
            Toast.makeText(context, "再次返回退出应用", Toast.LENGTH_SHORT).show()
            scope.launch {
                delay(2000)
                backPressedOnce = false
            }
        }
    }

    var query by remember { mutableStateOf("") }
    var selectedCategory by remember { mutableStateOf("全部") }

    // 顶部分类标签根据实际保险库记录动态生成（不写死）。
    val actualCategories = remember(items) {
        items.map { it.category }
            .map { it.trim() }
            .filter { it.isNotBlank() }
            .distinct()
    }
    // 选中的分类若已不存在（如相关记录被全部删除），回落到「全部」。
    val effectiveCategory =
        if (selectedCategory != "全部" && selectedCategory !in actualCategories) "全部" else selectedCategory

    val filtered = items.filter { item ->
        val inCat = effectiveCategory == "全部" || item.category == effectiveCategory
        val inQuery = query.isBlank() ||
            item.title.contains(query, ignoreCase = true) ||
            item.username.contains(query, ignoreCase = true)
        inCat && inQuery
    }
    val hasConflicts = false

    Scaffold(
        topBar = {
            PwdlockTopBar(
                title = "",
                onBack = null,
                leading = {
                    IconButton(
                        onClick = {
                            VaultSession.lock()
                            navController.navigate(Screen.AutoLock.route) {
                                popUpTo(Screen.ModeSelect.route)
                                launchSingleTop = true
                            }
                        },
                    ) {
                        Icon(Icons.Filled.Lock, contentDescription = "立即锁定")
                    }
                },
                actions = {
                    IconButton(onClick = { navController.navigate(Screen.Settings.route) }) {
                        Icon(Icons.Filled.Settings, contentDescription = "设置")
                    }
                },
            )
        },
        floatingActionButton = {
            FloatingActionButton(
                onClick = { navController.navigate("item_edit") },
                containerColor = MaterialTheme.colorScheme.primary,
                contentColor = MaterialTheme.colorScheme.onPrimary,
            ) {
                Icon(Icons.Filled.Add, contentDescription = "新增登录项")
            }
        },
    ) { inner ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(inner),
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = ScreenHMargin, vertical = SpaceMD),
                verticalArrangement = Arrangement.spacedBy(SpaceMD),
            ) {
                PwdlockSearchBar(
                    value = query,
                    onValueChange = { query = it },
                    placeholder = "搜索标题或账号",
                )

                LazyRow(
                    horizontalArrangement = Arrangement.spacedBy(SpaceSM),
                    contentPadding = PaddingValues(horizontal = 2.dp),
                ) {
                    val cats = listOf("全部") + actualCategories
                    items(cats) { cat ->
                        FilterChip(
                            selected = effectiveCategory == cat,
                            onClick = { selectedCategory = cat },
                            label = { Text(cat) },
                        )
                    }
                }
            }

            if (hasConflicts) {
                ConflictBanner(
                    count = 0,
                    onClick = { navController.navigate(Screen.ConflictCenter.route) },
                )
            }

            if (filtered.isEmpty()) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = if (items.isEmpty()) "还没有登录项，点击右下角添加" else "没有匹配的登录项",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    items(filtered, key = { it.id }) { item ->
                        VaultItemRow(
                            item = item,
                            onClick = { navController.navigate("item_detail/${item.id}") },
                        )
                        HorizontalDivider(
                            color = MaterialTheme.colorScheme.outline,
                            thickness = 1.dp,
                            modifier = Modifier.padding(start = SpaceLG + 44.dp + SpaceMD, end = SpaceLG),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ConflictBanner(count: Int, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = ScreenHMargin, vertical = SpaceSM)
            .clip(RoundedCornerShape(RadiusMD))
            .background(PwdlockColors.WarningContainer)
            .clickable(onClick = onClick)
            .padding(SpaceLG),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                imageVector = Icons.Filled.Warning,
                contentDescription = null,
                tint = PwdlockColors.Warning,
                modifier = Modifier.padding(end = SpaceMD),
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "$count 个冲突待处理",
                    style = MaterialTheme.typography.bodyLarge,
                    color = PwdlockColors.Warning,
                )
                Text(
                    text = "导入产生了冲突，需你裁决",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Icon(
                imageVector = Icons.AutoMirrored.Filled.ArrowForward,
                contentDescription = null,
                tint = PwdlockColors.Warning,
            )
        }
    }
}
