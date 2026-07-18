package com.pwdlock.android.data.settings

import android.content.Context
import android.content.SharedPreferences

/**
 * 本地模式设置的持久化存储（明文偏好项）。
 *
 * 只保存「设置状态」，不保存任何密钥明文：
 * - 生物识别包装后的 vaultKey 密文（[bioCiphertext]）由 Android Keystore 密钥加密，
 *   即使被读取也无法在无指纹认证的情况下解出。
 * - 自动锁定时长、切后台锁定开关等纯配置项。
 */
class SettingsStore(context: Context) {
    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    // region 生物识别

    var biometricEnabled: Boolean
        get() = prefs.getBoolean(KEY_BIO_ENABLED, false)
        set(value) { prefs.edit().putBoolean(KEY_BIO_ENABLED, value).apply() }

    /** Keystore 密钥加密后的 vaultKey 密文（Base64）。 */
    var bioCiphertext: String?
        get() = prefs.getString(KEY_BIO_CIPHERTEXT, null)
        set(value) { prefs.edit().putString(KEY_BIO_CIPHERTEXT, value).apply() }

    /** 上述密文对应的 GCM IV（Base64）。 */
    var bioIv: String?
        get() = prefs.getString(KEY_BIO_IV, null)
        set(value) { prefs.edit().putString(KEY_BIO_IV, value).apply() }

    fun clearBiometric() {
        prefs.edit()
            .remove(KEY_BIO_ENABLED)
            .remove(KEY_BIO_CIPHERTEXT)
            .remove(KEY_BIO_IV)
            .apply()
    }

    // endregion

    // region 自动锁定

    /**
     * 前台闲置多少分钟后锁定。0 表示「不做闲置锁定」（仍会在切到后台时锁定）。
     * 默认 5 分钟。
     */
    var autoLockMinutes: Int
        get() = prefs.getInt(KEY_AUTOLOCK_MINUTES, DEFAULT_AUTOLOCK_MINUTES)
        set(value) { prefs.edit().putInt(KEY_AUTOLOCK_MINUTES, value).apply() }

    /** 切到后台是否立即锁定（默认开启，最安全）。 */
    var lockOnBackground: Boolean
        get() = prefs.getBoolean(KEY_LOCK_ON_BACKGROUND, true)
        set(value) { prefs.edit().putBoolean(KEY_LOCK_ON_BACKGROUND, value).apply() }

    // endregion

    companion object {
        private const val PREFS_NAME = "pwdlock_settings"
        private const val KEY_BIO_ENABLED = "bio_enabled"
        private const val KEY_BIO_CIPHERTEXT = "bio_ciphertext"
        private const val KEY_BIO_IV = "bio_iv"
        private const val KEY_AUTOLOCK_MINUTES = "autolock_minutes"
        private const val KEY_LOCK_ON_BACKGROUND = "lock_on_background"

        const val DEFAULT_AUTOLOCK_MINUTES = 5

        /** 可选的闲置锁定时长（分钟）。0 = 从不（仅切后台锁定）。 */
        val AUTOLOCK_OPTIONS = listOf(1, 5, 15, 0)

        fun autoLockLabel(minutes: Int): String = when (minutes) {
            0 -> "从不（仅切后台锁定）"
            1 -> "1 分钟"
            else -> "$minutes 分钟"
        }
    }
}
