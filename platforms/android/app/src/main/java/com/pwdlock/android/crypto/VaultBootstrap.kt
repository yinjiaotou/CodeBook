package com.pwdlock.android.crypto

/**
 * 复刻 macOS `VaultBootstrap.create`：创建新保险库。
 * 生成随机 32 字节 vaultKey 与随机 vaultID / passwordSalt / wrapNonce，
 * 用主密码包装成 [VaultMetadata]。
 */
object VaultBootstrap {
    data class CreatedVault(val metadata: VaultMetadata, val vaultKey: ByteArray)

    fun create(masterPassword: String): CreatedVault {
        val vaultKey = CryptoIO.randomBytes(32)
        val metadata = VaultKeyEnvelope.wrap(
            vaultKey = vaultKey,
            masterPassword = masterPassword,
            vaultID = CryptoIO.randomBytes(16),
            passwordSalt = CryptoIO.randomBytes(16),
            wrapNonce = CryptoIO.randomBytes(12),
        )
        return CreatedVault(metadata, vaultKey)
    }
}
