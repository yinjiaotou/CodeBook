package com.pwdlock.android.data

import android.content.Context
import android.content.SharedPreferences

/**
 * 导航层偏好：记录「上次激活的运行模式」。
 *
 * 仅保存一个非敏感标记（"online" / "local"），用于 App 启动时决定首屏，
 * 避免每次都从模式选择页重新选、在线模式下还要重输账号。
 * 与业务无关——不存放任何账户/密钥/记录信息，也不属于本地或在线任一业务模块。
 */
object AppModePrefs {
    private const val FILE = "pwdlock_app_prefs"
    private const val K_LAST_MODE = "lastMode" // "online" | "local"

    fun lastMode(context: Context): String {
        val v = prefs(context).getString(K_LAST_MODE, "") ?: ""
        return if (v == "online" || v == "local") v else ""
    }

    fun setLastMode(context: Context, mode: String) {
        require(mode == "online" || mode == "local") { "invalid mode: $mode" }
        prefs(context).edit().putString(K_LAST_MODE, mode).apply()
    }

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
}
