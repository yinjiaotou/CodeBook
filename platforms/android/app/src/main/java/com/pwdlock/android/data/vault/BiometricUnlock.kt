package com.pwdlock.android.data.vault

import android.content.Context
import android.os.Build
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.util.Base64
import androidx.annotation.RequiresApi
import com.pwdlock.android.crypto.BiometricKeystore
import com.pwdlock.android.data.settings.SettingsStore
import com.pwdlock.android.util.BiometricAuth

/**
 * 指纹解锁编排：把 [BiometricKeystore]（Keystore 包装密钥）、[SettingsStore]（密文持久化）
 * 与 [VaultSession]（解锁）连起来。仅用于本地模式主密码解锁处。
 */
object BiometricUnlock {

    /** 设备支持指纹且系统 API 满足。 */
    fun deviceSupported(context: Context): Boolean = BiometricAuth.isAvailable(context)

    /** 已启用且存在可用密文，可在解锁页提供指纹入口。 */
    fun canOfferUnlock(context: Context): Boolean {
        val s = SettingsStore(context)
        return s.biometricEnabled && s.bioCiphertext != null && s.bioIv != null && deviceSupported(context)
    }

    fun isEnabled(context: Context): Boolean = SettingsStore(context).biometricEnabled

    /**
     * 启用指纹解锁：要求当前已解锁（内存中有 vaultKey）。
     * 指纹认证后用 Keystore 密钥加密 vaultKey 并落盘。
     */
    @RequiresApi(Build.VERSION_CODES.P)
    fun enable(
        context: Context,
        onDone: () -> Unit,
        onError: (String) -> Unit,
        onCancel: () -> Unit,
    ) {
        val vaultKey = VaultSession.vaultKey
        if (vaultKey == null) {
            onError("请先解锁密码库再开启指纹")
            return
        }
        val cipher = try {
            BiometricKeystore.encryptCipher()
        } catch (e: Exception) {
            onError("无法创建安全密钥：${e.message}")
            return
        }
        BiometricAuth.authenticate(
            context = context,
            title = "开启指纹解锁",
            subtitle = "用指纹保护你的密码库",
            cipher = cipher,
            onSuccess = { authed ->
                try {
                    val ciphertext = authed.doFinal(vaultKey)
                    val store = SettingsStore(context)
                    store.bioCiphertext = Base64.encodeToString(ciphertext, Base64.NO_WRAP)
                    store.bioIv = Base64.encodeToString(authed.iv, Base64.NO_WRAP)
                    store.biometricEnabled = true
                    onDone()
                } catch (e: Exception) {
                    onError("保存失败：${e.message}")
                }
            },
            onError = onError,
            onCancel = onCancel,
        )
    }

    /** 关闭指纹解锁：删除 Keystore 密钥并清空密文。 */
    fun disable(context: Context) {
        BiometricKeystore.deleteKey()
        SettingsStore(context).clearBiometric()
    }

    /**
     * 指纹解锁：认证后解出 vaultKey 并进入会话。
     * 指纹已变更（密钥失效）时自动关闭指纹并提示改用主密码。
     */
    @RequiresApi(Build.VERSION_CODES.P)
    fun unlock(
        context: Context,
        onSuccess: () -> Unit,
        onError: (String) -> Unit,
        onCancel: () -> Unit,
    ) {
        val store = SettingsStore(context)
        val ctB64 = store.bioCiphertext
        val ivB64 = store.bioIv
        if (ctB64 == null || ivB64 == null) {
            onError("尚未开启指纹解锁")
            return
        }
        val iv = Base64.decode(ivB64, Base64.NO_WRAP)
        val ciphertext = Base64.decode(ctB64, Base64.NO_WRAP)
        val cipher = try {
            BiometricKeystore.decryptCipher(iv)
        } catch (_: KeyPermanentlyInvalidatedException) {
            disable(context)
            onError("检测到指纹变更，请用主密码解锁")
            return
        } catch (e: Exception) {
            onError("指纹密钥不可用：${e.message}")
            return
        }
        BiometricAuth.authenticate(
            context = context,
            title = "指纹解锁",
            subtitle = "验证指纹以解锁密码库",
            cipher = cipher,
            onSuccess = { authed ->
                try {
                    val vaultKey = authed.doFinal(ciphertext)
                    if (VaultSession.unlockWithVaultKey(context, vaultKey)) {
                        onSuccess()
                    } else {
                        // 指纹认证通过、也解出了 vaultKey，但这把 key 已打不开当前保险库
                        // （封存的凭据过期 / 保险库被重建）。自动关闭指纹，回退主密码，避免永久卡死。
                        disable(context)
                        onError("指纹凭据已失效，请用主密码解锁后重新开启指纹")
                    }
                } catch (e: Exception) {
                    onError("指纹解锁失败：${e.message}")
                }
            },
            onError = onError,
            onCancel = onCancel,
        )
    }
}
