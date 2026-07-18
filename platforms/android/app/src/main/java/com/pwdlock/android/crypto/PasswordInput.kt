package com.pwdlock.android.crypto

import java.text.Normalizer

/**
 * 复刻 macOS `PasswordInput.utf8NFC`：与 Swift 的
 * `precomposedStringWithCanonicalMapping`（NFC 归一化）对齐，
 * 保证同一密码在 macOS / Android 派生出相同的 KEK 字节。
 */
object PasswordInput {
    /** 返回 NFC 归一化后的字符数组，作为 Argon2id 的密码输入。 */
    fun nfcChars(password: String): CharArray =
        Normalizer.normalize(password, Normalizer.Form.NFC).toCharArray()

    /** 返回 NFC 归一化后的字符串。 */
    fun nfcString(password: String): String =
        Normalizer.normalize(password, Normalizer.Form.NFC)
}
