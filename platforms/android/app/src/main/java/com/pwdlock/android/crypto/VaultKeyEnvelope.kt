package com.pwdlock.android.crypto

class VaultKeyEnvelopeException(message: String, cause: Throwable? = null) : Exception(message, cause)

/**
 * 复刻 macOS `VaultKeyEnvelope`：用主密码把 32 字节 vaultKey 包装 / 解包成 [VaultMetadata]。
 *
 * - KEK = Argon2id(主密码, passwordSalt, 参数)
 * - AES-GCM 以 wrapNonce 加密 vaultKey，AAD 为 metadata 编码后的前 52 字节
 * - 密码错误或数据损坏统一抛 [VaultKeyEnvelopeException]
 */
object VaultKeyEnvelope {
    fun wrap(
        vaultKey: ByteArray,
        masterPassword: String,
        vaultID: ByteArray,
        passwordSalt: ByteArray,
        wrapNonce: ByteArray,
        params: Argon2id.Params = Argon2id.initial,
    ): VaultMetadata {
        require(vaultKey.size == 32) { "vaultKey must be 32 bytes" }
        val template = VaultMetadata(
            vaultID = vaultID,
            memoryKiB = params.memoryKiB,
            iterations = params.iterations,
            parallelism = params.parallelism,
            passwordSalt = passwordSalt,
            wrapNonce = wrapNonce,
            wrappedVaultKey = ByteArray(32),
            wrapTag = ByteArray(16),
        )
        val kek = Argon2id.deriveKey(masterPassword, passwordSalt, params)
        val sealed = AesGcm.seal(vaultKey, kek, wrapNonce, VaultMetadataCodec.authenticatedHeader(template))
        val (ct, tag) = AesGcm.split(sealed)
        return template.copy(wrappedVaultKey = ct, wrapTag = tag)
    }

    fun unwrap(metadata: VaultMetadata, masterPassword: String): ByteArray = try {
        val params = Argon2id.Params(metadata.memoryKiB, metadata.iterations, metadata.parallelism)
        val kek = Argon2id.deriveKey(masterPassword, metadata.passwordSalt, params)
        val sealed = AesGcm.join(metadata.wrappedVaultKey, metadata.wrapTag)
        AesGcm.open(sealed, kek, metadata.wrapNonce, VaultMetadataCodec.authenticatedHeader(metadata))
    } catch (e: Exception) {
        throw VaultKeyEnvelopeException("authentication failed", e)
    }
}
