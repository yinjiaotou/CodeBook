package com.pwdlock.android.crypto

import com.lambdapioneer.argon2kt.Argon2Kt
import com.lambdapioneer.argon2kt.Argon2Mode
import com.lambdapioneer.argon2kt.Argon2Version
import java.text.Normalizer

/**
 * 复刻 macOS `PwdlockCore/Security/Argon2id.swift` 的 `argon2id_hash_raw`。
 *
 * 参数与 macOS 实测完全一致：memoryKiB = 65536 (64 MiB)、iterations = 3、parallelism = 1，
 * 输出 32 字节 KEK（与 vaultKey 等长，用于 AES-GCM 包装）。
 *
 * 使用 Android 专用库 `argon2kt`（自带 bionic 原生库 libargon2jni.so），底层同样是
 * 参考版 phc-winner-argon2 C 实现（与 macOS 的 phc-crypto 同源）。在给定相同类型 /
 * 版本(v=19) / t / m(KiB) / p / 密码字节 / 盐 / 输出长度时，与 macOS 的
 * `argon2id_hash_raw` 产生**逐字节相同**的 KEK。
 *
 * 注意：不要使用桌面版 `de.mkammerer:argon2-jvm`（JNA 加载的是 glibc 版 libargon2.so，
 * 在 Android(bionic) 上运行会 UnsatisfiedLinkError / 闪退）。
 */
object Argon2id {
    // 构造时即加载原生库（SystemSoLoader → System.loadLibrary("argon2jni")）。
    private val argon2 = Argon2Kt()

    data class Params(val memoryKiB: Int, val iterations: Int, val parallelism: Int)

    val initial = Params(memoryKiB = 65_536, iterations = 3, parallelism = 1)

    /** 派生 32 字节 KEK。密码按 NFC 归一化为 UTF-8，与 macOS 对齐。 */
    fun deriveKey(password: String, salt: ByteArray, params: Params = initial): ByteArray {
        require(password.isNotEmpty()) { "password must not be empty" }
        require(salt.size >= 8) { "salt must be at least 8 bytes" }
        require(params.memoryKiB > 0 && params.iterations > 0 && params.parallelism > 0)
        val nfc = Normalizer.normalize(password, Normalizer.Form.NFC)
        val pwdBytes = nfc.toByteArray(Charsets.UTF_8)
        try {
            val result = argon2.hash(
                mode = Argon2Mode.ARGON2_ID,
                password = pwdBytes,
                salt = salt,
                tCostInIterations = params.iterations,
                mCostInKibibyte = params.memoryKiB,
                parallelism = params.parallelism,
                hashLengthInBytes = 32,
                version = Argon2Version.V13
            )
            return result.rawHashAsByteArray()
        } finally {
            // 尽快清除明文密码副本
            pwdBytes.fill(0)
        }
    }
}
