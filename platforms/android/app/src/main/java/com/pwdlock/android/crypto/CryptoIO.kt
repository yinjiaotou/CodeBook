package com.pwdlock.android.crypto

import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.security.SecureRandom

/** 二进制编解码与随机字节等小工具，供加密层复用。 */
object CryptoIO {
    fun randomBytes(n: Int): ByteArray = ByteArray(n).also { SecureRandom().nextBytes(it) }

    fun intToBe(v: Int): ByteArray = ByteBuffer.allocate(4).putInt(v).array()
    fun longToBe(v: Long): ByteArray = ByteBuffer.allocate(8).putLong(v).array()

    fun beToInt(b: ByteArray, off: Int): Int = ByteBuffer.wrap(b.copyOfRange(off, off + 4)).int
    fun beToLong(b: ByteArray, off: Int): Long = ByteBuffer.wrap(b.copyOfRange(off, off + 8)).long

    fun writeBytes(out: ByteArrayOutputStream, data: ByteArray) {
        out.write(data, 0, data.size)
    }
}
