package com.pwdlock.android.crypto

import java.io.ByteArrayOutputStream

/**
 * 复刻 macOS `VaultMetadata` 与 `VaultMetadataCodec`。
 *
 * 112 字节二进制格式：
 *   PVLT(4) + version(1) + vaultID(16) + algo(3: 0x01,0x01,0x00)
 *   + memoryKiB(4 BE) + iterations(4 BE) + parallelism(1) + reserved(3)
 *   + passwordSalt(16) + wrapNonce(12) + wrappedVaultKey(32) + wrapTag(16)
 *
 * AAD 认证头为编码结果的前 52 字节（覆盖到 passwordSalt 为止，不含 wrapNonce/key/tag）。
 */
data class VaultMetadata(
    val vaultID: ByteArray,
    val memoryKiB: Int,
    val iterations: Int,
    val parallelism: Int,
    val passwordSalt: ByteArray,
    val wrapNonce: ByteArray,
    val wrappedVaultKey: ByteArray,
    val wrapTag: ByteArray,
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false
        other as VaultMetadata
        return vaultID.contentEquals(other.vaultID) &&
            memoryKiB == other.memoryKiB &&
            iterations == other.iterations &&
            parallelism == other.parallelism &&
            passwordSalt.contentEquals(other.passwordSalt) &&
            wrapNonce.contentEquals(other.wrapNonce) &&
            wrappedVaultKey.contentEquals(other.wrappedVaultKey) &&
            wrapTag.contentEquals(other.wrapTag)
    }

    override fun hashCode(): Int {
        var result = vaultID.contentHashCode()
        result = 31 * result + memoryKiB
        result = 31 * result + iterations
        result = 31 * result + parallelism
        result = 31 * result + passwordSalt.contentHashCode()
        result = 31 * result + wrapNonce.contentHashCode()
        result = 31 * result + wrappedVaultKey.contentHashCode()
        result = 31 * result + wrapTag.contentHashCode()
        return result
    }
}

object VaultMetadataCodec {
    const val ENCODED_LENGTH = 112
    private val MAGIC = "PVLT".toByteArray(Charsets.US_ASCII)

    fun encode(m: VaultMetadata): ByteArray {
        require(m.vaultID.size == 16) { "vaultID must be 16 bytes" }
        require(m.passwordSalt.size == 16) { "passwordSalt must be 16 bytes" }
        require(m.wrapNonce.size == 12) { "wrapNonce must be 12 bytes" }
        require(m.wrappedVaultKey.size == 32) { "wrappedVaultKey must be 32 bytes" }
        require(m.wrapTag.size == 16) { "wrapTag must be 16 bytes" }

        val out = ByteArrayOutputStream(ENCODED_LENGTH)
        out.write(MAGIC)
        out.write(0x01)
        out.write(m.vaultID, 0, m.vaultID.size)
        out.write(byteArrayOf(0x01, 0x01, 0x00))
        out.write(CryptoIO.intToBe(m.memoryKiB))
        out.write(CryptoIO.intToBe(m.iterations))
        out.write(m.parallelism)
        out.write(byteArrayOf(0x00, 0x00, 0x00))
        out.write(m.passwordSalt, 0, m.passwordSalt.size)
        out.write(m.wrapNonce, 0, m.wrapNonce.size)
        out.write(m.wrappedVaultKey, 0, m.wrappedVaultKey.size)
        out.write(m.wrapTag, 0, m.wrapTag.size)
        return out.toByteArray()
    }

    fun decode(bytes: ByteArray): VaultMetadata {
        require(bytes.size == ENCODED_LENGTH) { "metadata must be $ENCODED_LENGTH bytes" }
        require(bytes.copyOfRange(0, 4).contentEquals(MAGIC)) { "invalid magic" }
        require(bytes[4] == 0x01.toByte()) { "unsupported version" }
        require(bytes[21] == 0x01.toByte() && bytes[22] == 0x01.toByte()) { "unsupported algorithm" }
        require(bytes[23] == 0x00.toByte()) { "invalid flags" }
        require(bytes[33] == 0x00.toByte() && bytes[34] == 0x00.toByte() && bytes[35] == 0x00.toByte()) { "invalid reserved" }

        return VaultMetadata(
            vaultID = bytes.copyOfRange(5, 21),
            memoryKiB = CryptoIO.beToInt(bytes, 24),
            iterations = CryptoIO.beToInt(bytes, 28),
            parallelism = bytes[32].toInt() and 0xFF,
            passwordSalt = bytes.copyOfRange(36, 52),
            wrapNonce = bytes.copyOfRange(52, 64),
            wrappedVaultKey = bytes.copyOfRange(64, 96),
            wrapTag = bytes.copyOfRange(96, 112),
        )
    }

    /** AAD 认证头：编码结果的前 52 字节（不含 wrapNonce / wrappedVaultKey / wrapTag）。 */
    fun authenticatedHeader(m: VaultMetadata): ByteArray = encode(m).copyOfRange(0, 52)
}
