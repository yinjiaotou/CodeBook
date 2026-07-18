package com.pwdlock.android.crypto

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * 指纹解锁使用的 Android Keystore 密钥（硬件安全区，永不导出）。
 *
 * 用途：用该密钥（要求指纹认证才能使用）把 32 字节 vaultKey 加密后存入偏好；
 * 解锁时经指纹认证解出 vaultKey，无需主密码。参考 macOS `BiometricVaultEnvelope`
 * 的「包装 vaultKey」思路，Android 侧改由 Keystore 托管包装密钥。
 *
 * 仅支持 API 28+（系统 BiometricPrompt）。开启「按指纹录入失效」——录入新指纹会使
 * 密钥失效，届时回退主密码解锁。
 */
object BiometricKeystore {
    private const val KEY_ALIAS = "pwdlock_bio_key"
    private const val ANDROID_KEYSTORE = "AndroidKeyStore"
    private const val TRANSFORMATION =
        "${KeyProperties.KEY_ALGORITHM_AES}/${KeyProperties.BLOCK_MODE_GCM}/${KeyProperties.ENCRYPTION_PADDING_NONE}"
    const val GCM_TAG_BITS = 128

    /** 仅系统 BiometricPrompt（API 28+）可用。 */
    fun isSupportedApi(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P

    private fun keyStore(): KeyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }

    private fun getOrCreateKey(): SecretKey {
        val ks = keyStore()
        (ks.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }

        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        val builder = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setUserAuthenticationRequired(true)
            .setInvalidatedByBiometricEnrollment(true)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // 每次使用都需生物识别认证（0 秒有效期）
            builder.setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
        } else {
            @Suppress("DEPRECATION")
            builder.setUserAuthenticationValidityDurationSeconds(-1)
        }
        generator.init(builder.build())
        return generator.generateKey()
    }

    /** 启用指纹解锁：返回 ENCRYPT 模式 Cipher（认证后 doFinal 加密 vaultKey）。 */
    fun encryptCipher(): Cipher {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        return cipher
    }

    /**
     * 指纹解锁：返回 DECRYPT 模式 Cipher（认证后 doFinal 解出 vaultKey）。
     * @throws KeyPermanentlyInvalidatedException 录入了新指纹导致密钥失效时。
     */
    fun decryptCipher(iv: ByteArray): Cipher {
        val ks = keyStore()
        val key = ks.getKey(KEY_ALIAS, null) as? SecretKey
            ?: throw KeyPermanentlyInvalidatedException("biometric key missing")
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(GCM_TAG_BITS, iv))
        return cipher
    }

    fun deleteKey() {
        runCatching { keyStore().deleteEntry(KEY_ALIAS) }
    }
}
