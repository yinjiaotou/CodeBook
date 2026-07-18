package com.pwdlock.android.crypto

import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * 复刻 macOS `CryptoKit.AES.GCM`：AES-256-GCM，12 字节 nonce，16 字节 (128-bit) tag。
 *
 * Java `Cipher` 的 `AES/GCM/NoPadding` 在 `doFinal` 时返回 `ciphertext || tag(16)`，
 * 与 CryptoKit 的 `sealed.ciphertext` / `sealed.tag` 拆分方式完全对应。
 * 认证失败（密码错误或数据损坏）抛出 [javax.crypto.AEADBadTagException]。
 */
object AesGcm {
    private const val TAG_BITS = 128
    const val NONCE_BYTES = 12
    const val TAG_BYTES = 16

    fun randomNonce(): ByteArray = ByteArray(NONCE_BYTES).also { SecureRandom().nextBytes(it) }

    fun seal(plaintext: ByteArray, key: ByteArray, nonce: ByteArray, aad: ByteArray? = null): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(TAG_BITS, nonce))
        aad?.let { cipher.updateAAD(it) }
        return cipher.doFinal(plaintext)
    }

    fun open(sealed: ByteArray, key: ByteArray, nonce: ByteArray, aad: ByteArray? = null): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(TAG_BITS, nonce))
        aad?.let { cipher.updateAAD(it) }
        return cipher.doFinal(sealed)
    }

    fun split(sealed: ByteArray): Pair<ByteArray, ByteArray> {
        require(sealed.size >= TAG_BYTES)
        val ciphertext = sealed.copyOfRange(0, sealed.size - TAG_BYTES)
        val tag = sealed.copyOfRange(sealed.size - TAG_BYTES, sealed.size)
        return ciphertext to tag
    }

    fun join(ciphertext: ByteArray, tag: ByteArray): ByteArray = ciphertext + tag
}
