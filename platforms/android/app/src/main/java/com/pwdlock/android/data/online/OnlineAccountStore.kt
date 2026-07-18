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
    private const val DEF_BASE_URL = "http://10.0.2.2:3000/v1"

    private const val K_TOKEN = "token"
    private const val K_LOGIN = "loginName"
    private const val K_VAULT = "vaultId"
    private const val K_DEVICE = "deviceId"
    private const val K_CURSOR = "cursor"
    private const val K_ENVELOPE = "envelope"
    private const val K_SEED = "signingSeed"
    private const val K_BASE_URL = "baseUrl"
    private const val K_LAST_SYNC = "lastSyncMs"

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
