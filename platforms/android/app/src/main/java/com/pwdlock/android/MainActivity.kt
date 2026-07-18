package com.pwdlock.android

import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.pwdlock.android.data.settings.SettingsStore
import com.pwdlock.android.data.vault.VaultSession
import com.pwdlock.android.navigation.PwdlockNavHost
import com.pwdlock.android.ui.theme.PwdlockTheme

/**
 * 承载前台闲置超时锁定：只要用户在前台一段时间内无任何交互，即锁定密码库。
 *
 * 与 [PwdlockApplication] 的「切后台立即锁定」叠加，构成用户选择的「两者都要」策略。
 * 闲置时长取 [SettingsStore.autoLockMinutes]，为 0 时不做前台闲置锁定（仅切后台锁）。
 */
class MainActivity : ComponentActivity() {

    private val idleHandler = Handler(Looper.getMainLooper())
    private val idleLockRunnable = Runnable {
        // 导入流程进行中豁免前台闲置锁定，避免用户在导入预览页停留时被误锁。
        if (VaultSession.importFlowActive) return@Runnable
        if (VaultSession.isUnlocked()) VaultSession.lock()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            PwdlockTheme {
                PwdlockNavHost()
            }
        }
    }

    /** 每次用户交互都重置闲置计时。 */
    override fun onUserInteraction() {
        super.onUserInteraction()
        rescheduleIdleLock()
    }

    override fun onResume() {
        super.onResume()
        rescheduleIdleLock()
    }

    override fun onPause() {
        super.onPause()
        idleHandler.removeCallbacks(idleLockRunnable)
    }

    private fun rescheduleIdleLock() {
        idleHandler.removeCallbacks(idleLockRunnable)
        val minutes = SettingsStore(this).autoLockMinutes
        if (minutes > 0 && VaultSession.isUnlocked()) {
            idleHandler.postDelayed(idleLockRunnable, minutes * 60_000L)
        }
    }
}
