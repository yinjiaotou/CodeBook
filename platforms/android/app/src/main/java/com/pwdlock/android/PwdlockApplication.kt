package com.pwdlock.android

import android.app.Application
import android.os.Process
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import androidx.lifecycle.lifecycleScope
import com.pwdlock.android.data.settings.SettingsStore
import com.pwdlock.android.data.vault.VaultSession
import kotlinx.coroutines.launch
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter

/**
 * 应用级上下文。负责「切后台立即锁定」这一进程级自动锁定策略，以及「切回前台自动同步」。
 *
 * 通过 [ProcessLifecycleOwner] 监听整个进程的前后台切换：
 * - 进程进入后台（[DefaultLifecycleObserver.onStop]）时，若用户开启了「切后台锁定」
 *   且当前处于解锁态，则立即清空内存中的 vaultKey。
 * - 进程回到前台（[DefaultLifecycleObserver.onStart]）时，若处于在线模式且已解锁，
 *   则自动触发一次同步（拉取远端变更 + 补传离线队列）。失败静默，不阻塞前台使用。
 *
 * 前台闲置超时锁定由 [MainActivity] 通过用户交互计时实现（两种策略叠加）。
 */
class PwdlockApplication : Application() {

    override fun onCreate() {
        super.onCreate()
        installCrashHandler()
        ProcessLifecycleOwner.get().lifecycle.addObserver(
            object : DefaultLifecycleObserver {
                override fun onStop(owner: LifecycleOwner) {
                    // 进程切到后台：默认立即锁定（用户不再需要开关；最安全策略）。
                    // 导入流程进行中（停留在导入预览页）豁免切后台锁定，避免「确认导入」被中断。
                    if (VaultSession.importFlowActive) return
                    if (VaultSession.isUnlocked()) {
                        VaultSession.lock()
                    }
                }

                override fun onStart(owner: LifecycleOwner) {
                    // 进程回到前台：在线模式且已解锁时自动同步（拉取 + 补传）。
                    if (VaultSession.isUnlocked() && VaultSession.onlineMode) {
                        owner.lifecycleScope.launch {
                            try {
                                VaultSession.sync(this@PwdlockApplication)
                            } catch (_: Exception) {
                                // 同步失败（如网络不可用）静默，不阻塞前台使用。
                            }
                        }
                    }
                }
            }
        )
    }

    /**
     * 全局未捕获异常捕获器：把崩溃堆栈写入 [CRASH_LOG]，供下次启动时在首屏展示，
     * 便于快速定位「直接闪退」类问题（普通 logcat 不易获取时使用）。捕获后仍交给原 handler
     * 让进程按系统默认行为终止，保证行为可预期。
     */
    private fun installCrashHandler() {
        val default = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                val sw = StringWriter()
                throwable.printStackTrace(PrintWriter(sw))
                val header = "time=${System.currentTimeMillis()}\nthread=${thread.name}\n"
                File(filesDir, CRASH_LOG).writeText(header + sw.toString())
            } catch (_: Exception) {
                // 忽略写入失败
            }
            default?.uncaughtException(thread, throwable)
        }
    }

    companion object {
        /** 崩溃日志文件名（位于应用 filesDir）。 */
        const val CRASH_LOG = "crash.log"
    }
}
