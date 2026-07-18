package com.pwdlock.android.crypto

import com.pwdlock.android.data.model.PwdlockPayload
import com.pwdlock.android.data.vault.VaultJson
import java.io.ByteArrayOutputStream

/**
 * 复刻 macOS `.pwdlock` v1 归档（导出 / 导入），与 macOS 完全二进制兼容。
 *
 * 116 字节头：`PWLK`(4) + 1,1,1,0(4) + memoryKiB(4) + iterations(4)
 * + parallelism(1) + reserved(3) + salt(16) + wrapNonce(12)
 * + wrappedExportKey(32) + wrapTag(16) + payloadNonce(12) + plaintextLen(8 BE)
 * 之后是 `ciphertext(plaintextLen)` + `payloadTag(16)`。
 *
 * - 导出 Key 由导出密码经 Argon2id 派生 KEK，AES-GCM 包装；AAD = 头前 36 字节。
 * - 负载由导出 Key 经 AES-GCM 加密；AAD = 完整 116 字节头。
 * 密码错误或文件损坏统一抛 [PwdlockArchiveException]。
 */
class PwdlockArchiveException(message: String, cause: Throwable? = null) : Exception(message, cause)

object PwdlockArchive {
    private const val HEADER_LENGTH = 116
    private const val TAG_LENGTH = 16
    private val MAGIC = "PWLK".toByteArray(Charsets.US_ASCII)
    private val PARAMS = Argon2id.initial

    fun export(payload: PwdlockPayload, password: String): ByteArray {
        val plaintext = VaultJson.encodePayload(payload).toByteArray(Charsets.UTF_8)
        val salt = CryptoIO.randomBytes(16)
        val wrapNonce = CryptoIO.randomBytes(12)
        val exportKey = CryptoIO.randomBytes(32)
        val payloadNonce = AesGcm.randomNonce()

        val header = ByteArrayOutputStream(HEADER_LENGTH)
        header.write(MAGIC)
        header.write(byteArrayOf(1, 1, 1, 0))
        header.write(CryptoIO.intToBe(PARAMS.memoryKiB))
        header.write(CryptoIO.intToBe(PARAMS.iterations))
        header.write(PARAMS.parallelism)
        header.write(byteArrayOf(0, 0, 0))
        header.write(salt, 0, salt.size)
        header.write(wrapNonce, 0, wrapNonce.size)

        val kek = Argon2id.deriveKey(password, salt, PARAMS)
        val wrapped = AesGcm.seal(exportKey, kek, wrapNonce, header.toByteArray().copyOfRange(0, 36))
        val (wct, wtag) = AesGcm.split(wrapped)
        header.write(wct, 0, wct.size)
        header.write(wtag, 0, wtag.size)
        header.write(payloadNonce, 0, payloadNonce.size)
        header.write(CryptoIO.longToBe(plaintext.size.toLong()))

        val encrypted = AesGcm.seal(plaintext, exportKey, payloadNonce, header.toByteArray())
        val (pct, ptag) = AesGcm.split(encrypted)
        header.write(pct, 0, pct.size)
        header.write(ptag, 0, ptag.size)
        return header.toByteArray()
    }

    fun `import`(data: ByteArray, password: String): PwdlockPayload = try {
        require(data.size >= HEADER_LENGTH) { "archive too small" }
        require(data.copyOfRange(0, 4).contentEquals(MAGIC)) { "invalid magic" }
        require(
            data[4] == 1.toByte() && data[5] == 1.toByte() &&
                data[6] == 1.toByte() && data[7] == 0.toByte()
        ) { "unsupported version/algorithm" }
        require(data[17] == 0.toByte() && data[18] == 0.toByte() && data[19] == 0.toByte()) { "invalid reserved" }

        val memory = CryptoIO.beToInt(data, 8)
        val iterations = CryptoIO.beToInt(data, 12)
        val lanes = data[16].toInt() and 0xFF
        require(memory in 65_536..262_144 && iterations in 3..10 && lanes in 1..4) { "unsupported parameters" }

        val length = CryptoIO.beToLong(data, 108)
        val expected = HEADER_LENGTH + length + TAG_LENGTH
        require(data.size.toLong() == expected) { "corrupt archive length" }

        val salt = data.copyOfRange(20, 36)
        val wrapNonce = data.copyOfRange(36, 48)
        val wrappedKey = data.copyOfRange(48, 80)
        val wrapTag = data.copyOfRange(80, 96)
        val payloadNonce = data.copyOfRange(96, 108)
        val ciphertext = data.copyOfRange(HEADER_LENGTH, HEADER_LENGTH + length.toInt())
        val payloadTag = data.copyOfRange(HEADER_LENGTH + length.toInt(), data.size)

        val params = Argon2id.Params(memory, iterations, lanes)
        val kek = Argon2id.deriveKey(password, salt, params)
        val exportKey = AesGcm.open(AesGcm.join(wrappedKey, wrapTag), kek, wrapNonce, data.copyOfRange(0, 36))
        require(exportKey.size == 32) { "export key length mismatch" }
        val plaintext = AesGcm.open(AesGcm.join(ciphertext, payloadTag), exportKey, payloadNonce, data.copyOfRange(0, HEADER_LENGTH))
        VaultJson.decodePayload(String(plaintext, Charsets.UTF_8))
    } catch (e: PwdlockArchiveException) {
        throw e
    } catch (e: Exception) {
        throw PwdlockArchiveException("authentication failed", e)
    }
}
