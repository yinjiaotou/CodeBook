package com.pwdlock.android

import android.app.Application
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import com.pwdlock.android.data.settings.SettingsStore
import com.pwdlock.android.data.vault.VaultSession

/**
 * 应用级上下文。负责「切后台立即锁定」这一进程级自动锁定策略。
 *
 * 通过 [ProcessLifecycleOwner] 监听整个进程的前后台切换：
 * - 进程进入后台（[DefaultLifecycleObserver.onStop]）时，若用户开启了「切后台锁定」
 *   且当前处于解锁态，则立即清空内存中的 vaultKey。
 *
 * 前台闲置超时锁定由 [MainActivity] 通过用户交互计时实现（两种策略叠加）。
 */
class PwdlockApplication : Application() {

    override fun onCreate() {
        super.onCreate()
        ProcessLifecycleOwner.get().lifecycle.addObserver(
            object : DefaultLifecycleObserver {
                override fun onStop(owner: LifecycleOwner) {
                    // 进程切到后台
                    val lockOnBackground = SettingsStore(this@PwdlockApplication).lockOnBackground
                    // 导入流程进行中（停留在导入预览页）豁免切后台锁定，避免「确认导入」被中断。
                    if (VaultSession.importFlowActive) return
                    if (lockOnBackground && VaultSession.isUnlocked()) {
                        VaultSession.lock()
                    }
                }
            }
        )
    }
}
