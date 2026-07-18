package com.pwdlock.android.crypto.online

import android.util.Base64
import com.pwdlock.android.crypto.AesGcm
import org.bouncycastle.crypto.digests.SHA256Digest
import java.security.MessageDigest
import org.bouncycastle.crypto.generators.HKDFBytesGenerator
import org.bouncycastle.crypto.params.HKDFParameters
import org.bouncycastle.crypto.params.Ed25519PrivateKeyParameters
import org.bouncycastle.crypto.params.Ed25519PublicKeyParameters
import org.bouncycastle.crypto.signers.Ed25519Signer
import java.security.SecureRandom

/**
 * 在线同步的端到端加密原语（对齐 macOS `OnlineSyncEnvelope` + 协议 `online-sync-v1.md`）。
 *
 * 服务端只保存密文与签名，不解密。所有加解密、验签均在客户端完成。
 *
 * 变更密钥：HKDF-SHA256(Vault Key, salt="", info="pwdlock.sync.v1.change", 32B)。
 * 变更 AAD：`pwdlock.sync.v1 | <lowercase vaultId> | <lowercase changeId>`。
 * 签名消息：`pwdlock.sync.v1` + NUL + <lowercase vaultId> + NUL + <lowercase changeId> + NUL + <ciphertext(base64)>。
 *
 * 设备签名密钥为每设备 Ed25519 密钥对（参考 macOS，不派生自 Vault Key）。
 * 使用 BouncyCastle 的底层 crypto API（minSdk 26 平台无原生 Ed25519/HKDF）。
 */
object OnlineSyncCrypto {
    private const val PROTOCOL_LABEL = "pwdlock.sync.v1"
    private const val CHANGE_CONTEXT = "pwdlock.sync.v1.change"
    private val EMPTY = ByteArray(0)

    private val random = SecureRandom()

    /** 从 Vault Key 派生变更加密密钥（32 字节）。 */
    fun deriveChangeKey(vaultKey: ByteArray): ByteArray {
        require(vaultKey.size == 32) { "vaultKey must be 32 bytes" }
        val hkdf = HKDFBytesGenerator(SHA256Digest())
        hkdf.init(HKDFParameters(vaultKey, EMPTY, CHANGE_CONTEXT.toByteArray(Charsets.UTF_8)))
        val out = ByteArray(32)
        hkdf.generateBytes(out, 0, 32)
        return out
    }

    /** 生成设备 Ed25519 密钥对。返回 (seed 32 字节, raw 公钥 32 字节)。seed 需安全持久化。 */
    fun generateDeviceKey(): Pair<ByteArray, ByteArray> {
        val seed = ByteArray(32).also { random.nextBytes(it) }
        val priv = Ed25519PrivateKeyParameters(seed, 0)
        val pubRaw = priv.generatePublicKey().encoded // Ed25519PublicKeyParameters.getEncoded() = 32 字节原始公钥
        return seed to pubRaw
    }

    /** 用设备私钥(seed)对消息签名，返回 64 字节原始签名。 */
    fun sign(seed: ByteArray, message: ByteArray): ByteArray {
        val signer = Ed25519Signer()
        signer.init(true, Ed25519PrivateKeyParameters(seed, 0))
        signer.update(message, 0, message.size)
        return signer.generateSignature()
    }

    /** 用设备原始公钥验证签名。 */
    fun verify(publicRaw: ByteArray, message: ByteArray, signature: ByteArray): Boolean {
        val signer = Ed25519Signer()
        signer.init(false, Ed25519PublicKeyParameters(publicRaw, 0))
        signer.update(message, 0, message.size)
        return signer.verifySignature(signature)
    }

    private fun changeAad(vaultId: String, changeId: String): ByteArray =
        "$PROTOCOL_LABEL | ${vaultId.lowercase()} | ${changeId.lowercase()}".toByteArray(Charsets.UTF_8)

    private fun signatureMessage(vaultId: String, changeId: String, ciphertext: String): ByteArray =
        "$PROTOCOL_LABEL\u0000${vaultId.lowercase()}\u0000${changeId.lowercase()}\u0000$ciphertext"
            .toByteArray(Charsets.UTF_8)

    /**
     * 封存一条变更：AES-256-GCM 加密明文（AAD 绑定 vaultId/changeId），再用设备私钥签名为密文背书。
     * @return 上传所需的信封（ciphertext/signature 均为 base64；changeId 为小写 UUID 文本）。
     */
    fun seal(
        plaintext: ByteArray,
        vaultId: String,
        changeId: String,
        vaultKey: ByteArray,
        signingSeed: ByteArray,
    ): OnlineSyncEnvelope {
        val changeKey = deriveChangeKey(vaultKey)
        // nonce 由 changeId 派生（确定性），保证同一逻辑变更重发时密文/签名完全一致，
        // 服务端据此判定为幂等（201 而非 409）。changeId 唯一 ⇒ nonce 唯一，不违反"同密钥下 nonce 不复用"。
        val nonce = MessageDigest.getInstance("SHA-256").digest(changeId.toByteArray(Charsets.UTF_8)).copyOfRange(0, 12)
        val aad = changeAad(vaultId, changeId)
        val sealed = AesGcm.seal(plaintext, changeKey, nonce, aad) // nonce || ciphertext || tag
        val ciphertext = sealed.toBase64()
        val sig = sign(signingSeed, signatureMessage(vaultId, changeId, ciphertext)).toBase64()
        return OnlineSyncEnvelope(ciphertext, sig, changeId.lowercase())
    }

    /**
     * 打开一条变更：验签（使用变更所属设备的原始公钥）→ AES-256-GCM 解密。
     * 任何认证/签名失败均抛 [OnlineCryptoException]，调用方应拒绝该变更。
     */
    fun open(
        envelope: OnlineSyncEnvelope,
        vaultId: String,
        vaultKey: ByteArray,
        devicePublicRaw: ByteArray,
    ): ByteArray {
        val changeKey = deriveChangeKey(vaultKey)
        val ciphertextBytes = envelope.ciphertext.fromBase64()
        val signatureBytes = envelope.signature.fromBase64()
        val msg = signatureMessage(vaultId, envelope.changeId, envelope.ciphertext)
        if (!verify(devicePublicRaw, msg, signatureBytes)) {
            throw OnlineCryptoException("invalid change signature")
        }
        val aad = changeAad(vaultId, envelope.changeId)
        return AesGcm.open(ciphertextBytes, changeKey, ciphertextBytes.copyOfRange(0, 12), aad)
    }
}

/** 上传/下载用的已封存变更。ciphertext/signature 为 base64；changeId 为小写 UUID。 */
data class OnlineSyncEnvelope(
    val ciphertext: String,
    val signature: String,
    val changeId: String,
)

class OnlineCryptoException(message: String) : Exception(message)

// base64 扩展（URL 安全与否均可，这里用标准 Base64，与协议一致）
fun ByteArray.toBase64(): String = Base64.encodeToString(this, Base64.NO_WRAP)
fun String.fromBase64(): ByteArray = Base64.decode(this, Base64.NO_WRAP)
