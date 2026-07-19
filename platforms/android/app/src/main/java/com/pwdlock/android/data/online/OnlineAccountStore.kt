package com.pwdlock.android.data.online

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKeys

/**
 * 在线账户态的本地加密存储。
 *
 * 仅保存「认证与同步所需的非敏感或端侧加密材料」：
 * - 访问令牌（JWT，由 Android Keystore 主密钥加密）
 * - 登录名、服务端分配的 vaultId / deviceId
 * - 同步游标（最后拉取的 sequence）
 * - Vault Key 信封（base64，服务器返回的同款密文，本地仅用于离线解锁，本身不可解密）
 * - 设备 Ed25519 私钥 seed（base64，用于签署上传变更；绝不上传）
 *
 * 不保存主密码、Vault Key 明文或任何密码条目明文。
 */
object OnlineAccountStore {
    private const val FILE = "pwdlock_online_account"
    private const val DEF_BASE_URL = "http://124.223.115.40:3000/v1"

    private const val K_TOKEN = "token"
    private const val K_LOGIN = "loginName"
    private const val K_VAULT = "vaultId"
    private const val K_DEVICE = "deviceId"
    private const val K_CURSOR = "cursor"
    private const val K_ENVELOPE = "envelope"
    private const val K_SEED = "signingSeed"
    private const val K_BASE_URL = "baseUrl"
    private const val K_LAST_SYNC = "lastSyncMs"

    // 在线模式指纹解锁（独立字段，与本地 SettingsStore 的生物识别数据隔离）：
    // 仅保存 Keystore 加密后的 vaultKey 密文与 IV；密文本身不可解读，明文 vaultKey 永不落盘。
    private const val K_BIO_ENABLED = "bioEnabled"
    private const val K_BIO_CT = "bioCiphertext"
    private const val K_BIO_IV = "bioIv"

    private var prefs: SharedPreferences? = null

    @Synchronized
    private fun ensure(context: Context): SharedPreferences {
        prefs?.let { return it }
        val masterKeyAlias = MasterKeys.getOrCreate(MasterKeys.AES256_GCM_SPEC)
        val p = EncryptedSharedPreferences.create(
            FILE,
            masterKeyAlias,
            context.applicationContext,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
        prefs = p
        return p
    }

    fun token(context: Context): String? = ensure(context).getString(K_TOKEN, null)
    fun loginName(context: Context): String? = ensure(context).getString(K_LOGIN, null)
    fun vaultId(context: Context): String = ensure(context).getString(K_VAULT, "") ?: ""
    fun deviceId(context: Context): String = ensure(context).getString(K_DEVICE, "") ?: ""
    fun cursor(context: Context): String = ensure(context).getString(K_CURSOR, "0") ?: "0"
    fun envelope(context: Context): String = ensure(context).getString(K_ENVELOPE, "") ?: ""
    fun signingSeed(context: Context): String = ensure(context).getString(K_SEED, "") ?: ""
    fun baseUrl(context: Context): String = ensure(context).getString(K_BASE_URL, DEF_BASE_URL) ?: DEF_BASE_URL
    fun lastSyncMs(context: Context): Long = ensure(context).getLong(K_LAST_SYNC, 0L)

    fun hasToken(context: Context): Boolean = !token(context).isNullOrBlank()
    fun hasVault(context: Context): Boolean = vaultId(context).isNotBlank()
    fun hasDevice(context: Context): Boolean = deviceId(context).isNotBlank()

    // region 在线指纹解锁状态（独立存储，登出由 clear() 一并清除）

    fun bioEnabled(context: Context): Boolean = ensure(context).getBoolean(K_BIO_ENABLED, false)
    fun bioCiphertext(context: Context): String? = ensure(context).getString(K_BIO_CT, null)
    fun bioIv(context: Context): String? = ensure(context).getString(K_BIO_IV, null)

    /** 是否已真正具备可用指纹凭据（开关开 + 密文/IV 齐全）。解锁页据此决定是否提供指纹入口。 */
    fun hasBiometric(context: Context): Boolean =
        bioEnabled(context) && !bioCiphertext(context).isNullOrBlank() && !bioIv(context).isNullOrBlank()

    fun saveBiometric(context: Context, ctB64: String, ivB64: String) {
        ensure(context).edit()
            .putBoolean(K_BIO_ENABLED, true)
            .putString(K_BIO_CT, ctB64)
            .putString(K_BIO_IV, ivB64)
            .apply()
    }

    fun clearBiometric(context: Context) {
        ensure(context).edit()
            .remove(K_BIO_ENABLED)
            .remove(K_BIO_CT)
            .remove(K_BIO_IV)
            .apply()
    }

    // endregion

    fun saveCredentials(context: Context, token: String, loginName: String) {
        ensure(context).edit().putString(K_TOKEN, token).putString(K_LOGIN, loginName).apply()
    }

    fun saveVault(context: Context, vaultId: String, envelope: String) {
        ensure(context).edit().putString(K_VAULT, vaultId).putString(K_ENVELOPE, envelope).apply()
    }

    fun saveDevice(context: Context, deviceId: String, signingSeedB64: String) {
        ensure(context).edit().putString(K_DEVICE, deviceId).putString(K_SEED, signingSeedB64).apply()
    }

    fun saveCursor(context: Context, cursor: String) {
        ensure(context).edit().putString(K_CURSOR, cursor).apply()
    }

    fun saveLastSync(context: Context, ms: Long) {
        ensure(context).edit().putLong(K_LAST_SYNC, ms).apply()
    }

    fun setBaseUrl(context: Context, url: String) {
        ensure(context).edit().putString(K_BASE_URL, url).apply()
    }

    /** 登出：清除全部账户态（本地缓存由调用方另处清理）。 */
    fun clear(context: Context) {
        ensure(context).edit().clear().apply()
    }
}
