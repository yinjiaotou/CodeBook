package com.pwdlock.android.navigation

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.navigation.NavBackStackEntry
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.pwdlock.android.data.vault.VaultSession
import com.pwdlock.android.screen.AboutScreen
import com.pwdlock.android.screen.AutoLockScreen
import com.pwdlock.android.screen.ConflictCenterScreen
import com.pwdlock.android.screen.CreateMasterPasswordScreen
import com.pwdlock.android.screen.ExportPasswordScreen
import com.pwdlock.android.screen.ImportExportScreen
import com.pwdlock.android.screen.ImportPreviewScreen
import com.pwdlock.android.screen.ItemDetailScreen
import com.pwdlock.android.screen.ItemEditScreen
import com.pwdlock.android.screen.ModeSelectScreen
import com.pwdlock.android.screen.OnlineLoginScreen
import com.pwdlock.android.screen.OnlineMasterPasswordScreen
import com.pwdlock.android.screen.OnlineRegisterScreen
import com.pwdlock.android.screen.PasswordGeneratorScreen
import com.pwdlock.android.screen.SettingsScreen
import com.pwdlock.android.screen.UnlockScreen
import com.pwdlock.android.screen.VaultHomeScreen
import com.pwdlock.android.screen.WelcomeScreen

/**
 * 本地模式下需要解锁态才能停留的受保护页面。
 * 当自动锁定（切后台 / 前台闲置）触发、[VaultSession.unlocked] 变为 false 时，
 * 若用户正停留在这些页面，则跳转到「已锁定」页。
 */
private val ProtectedRoutes = setOf(
    Screen.VaultHome.route,
    Screen.ItemDetail.route,
    Screen.ItemEdit.route,
    Screen.Settings.route,
    Screen.ImportExport.route,
    Screen.ExportPassword.route,
    Screen.ImportPreview.route,
    Screen.PasswordGenerator.route,
    Screen.ConflictCenter.route,
    Screen.About.route,
)

@Composable
fun PwdlockNavHost(
    navController: NavHostController = rememberNavController(),
) {
    val unlocked by VaultSession.unlocked.collectAsState()
    val backStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = backStackEntry?.destination?.route

    // 自动锁定：解锁态被清空且当前停留在受保护页 → 跳转「已锁定」页。
    // 在线保险库锁定后需回到在线主密码页（而非本地解锁页）。
    LaunchedEffect(unlocked) {
        if (!unlocked && currentRoute != null && currentRoute in ProtectedRoutes) {
            val lockedRoute = if (VaultSession.onlineMode) Screen.OnlineMasterPassword.route else Screen.AutoLock.route
            navController.navigate(lockedRoute) {
                popUpTo(Screen.ModeSelect.route)
                launchSingleTop = true
            }
        }
    }

    NavHost(
        navController = navController,
        startDestination = Screen.ModeSelect.route,
        // 共享轴向（横向）+ 景深缩放：新页从右滑入并轻微放大、旧页向左滑出并微微放大后退，
        // 形成「推进入栈 / 弹出回退」的空间纵深感；返回时方向相反。作用于所有页面。
        enterTransition = {
            slideInHorizontally(
                initialOffsetX = { it },
                animationSpec = tween(durationMillis = 350, easing = FastOutSlowInEasing),
            ) + fadeIn(animationSpec = tween(350)) + scaleIn(
                initialScale = 0.96f,
                animationSpec = tween(durationMillis = 350, easing = FastOutSlowInEasing),
            )
        },
        exitTransition = {
            slideOutHorizontally(
                targetOffsetX = { -it },
                animationSpec = tween(durationMillis = 350, easing = FastOutSlowInEasing),
            ) + fadeOut(animationSpec = tween(350)) + scaleOut(
                targetScale = 1.04f,
                animationSpec = tween(durationMillis = 350, easing = FastOutSlowInEasing),
            )
        },
        popEnterTransition = {
            slideInHorizontally(
                initialOffsetX = { -it },
                animationSpec = tween(durationMillis = 350, easing = FastOutSlowInEasing),
            ) + fadeIn(animationSpec = tween(350)) + scaleIn(
                initialScale = 0.96f,
                animationSpec = tween(durationMillis = 350, easing = FastOutSlowInEasing),
            )
        },
        popExitTransition = {
            slideOutHorizontally(
                targetOffsetX = { it },
                animationSpec = tween(durationMillis = 350, easing = FastOutSlowInEasing),
            ) + fadeOut(animationSpec = tween(350)) + scaleOut(
                targetScale = 1.04f,
                animationSpec = tween(durationMillis = 350, easing = FastOutSlowInEasing),
            )
        },
    ) {
        composable(Screen.ModeSelect.route) { ModeSelectScreen(navController) }
        composable(Screen.Welcome.route) { WelcomeScreen(navController) }
        composable(Screen.OnlineLogin.route) { OnlineLoginScreen(navController) }
        composable(Screen.OnlineMasterPassword.route) { OnlineMasterPasswordScreen(navController) }
        composable(Screen.OnlineRegister.route) { OnlineRegisterScreen(navController) }
        composable(Screen.CreateMasterPassword.route) { CreateMasterPasswordScreen(navController) }
        composable(Screen.Unlock.route) { UnlockScreen(navController) }
        composable(Screen.VaultHome.route) { VaultHomeScreen(navController) }
        composable(Screen.ItemDetail.route) { backStackEntry ->
            ItemDetailScreen(navController, backStackEntry)
        }
        composable(Screen.ItemEdit.route) { backStackEntry ->
            ItemEditScreen(navController, backStackEntry)
        }
        composable(Screen.Settings.route) { SettingsScreen(navController) }
        composable(Screen.ImportExport.route) { ImportExportScreen(navController) }
        composable(Screen.ExportPassword.route) { ExportPasswordScreen(navController) }
        composable(Screen.ImportPreview.route) { ImportPreviewScreen(navController) }
        composable(Screen.PasswordGenerator.route) { PasswordGeneratorScreen(navController) }
        composable(Screen.ConflictCenter.route) { ConflictCenterScreen(navController) }
        composable(Screen.About.route) { AboutScreen(navController) }
        composable(Screen.AutoLock.route) { AutoLockScreen(navController) }
    }
}
