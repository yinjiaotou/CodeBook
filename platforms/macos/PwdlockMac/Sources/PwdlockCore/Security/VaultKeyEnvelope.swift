import CryptoKit
import Foundation

public enum VaultKeyEnvelopeError: Error, Equatable {
    case invalidVaultKey
    case authenticationFailed
}

public enum VaultKeyEnvelope {
    public static func wrap(
        vaultKey: Data,
        masterPassword: String,
        vaultID: Data,
        passwordSalt: Data,
        wrapNonce: Data,
        parameters: Argon2idParameters
    ) throws -> VaultMetadata {
        guard vaultKey.count == 32 else {
            throw VaultKeyEnvelopeError.invalidVaultKey
        }

        let template = VaultMetadata(
            vaultID: vaultID,
            memoryKiB: parameters.memoryKiB,
            iterations: parameters.iterations,
            parallelism: UInt8(exactly: parameters.parallelism) ?? 0,
            passwordSalt: passwordSalt,
            wrapNonce: wrapNonce,
            wrappedVaultKey: Data(repeating: 0, count: 32),
            wrapTag: Data(repeating: 0, count: 16)
        )
        let kek = try Argon2id.deriveKey(
            password: PasswordInput.utf8NFC(masterPassword),
            salt: passwordSalt,
            parameters: parameters
        )
        let nonce = try AES.GCM.Nonce(data: wrapNonce)
        let sealed = try AES.GCM.seal(
            vaultKey,
            using: SymmetricKey(data: kek),
            nonce: nonce,
            authenticating: VaultMetadataCodec.authenticatedHeader(for: template)
        )

        return VaultMetadata(
            vaultID: vaultID,
            memoryKiB: parameters.memoryKiB,
            iterations: parameters.iterations,
            parallelism: UInt8(exactly: parameters.parallelism) ?? 0,
            passwordSalt: passwordSalt,
            wrapNonce: wrapNonce,
            wrappedVaultKey: sealed.ciphertext,
            wrapTag: sealed.tag
        )
    }

    public static func unwrap(_ metadata: VaultMetadata, masterPassword: String) throws -> Data {
        do {
            let parameters = Argon2idParameters(
                memoryKiB: metadata.memoryKiB,
                iterations: metadata.iterations,
                parallelism: UInt32(metadata.parallelism)
            )
            let kek = try Argon2id.deriveKey(
                password: PasswordInput.utf8NFC(masterPassword),
                salt: metadata.passwordSalt,
                parameters: parameters
            )
            let box = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: metadata.wrapNonce),
                ciphertext: metadata.wrappedVaultKey,
                tag: metadata.wrapTag
            )
            return try AES.GCM.open(
                box,
                using: SymmetricKey(data: kek),
                authenticating: VaultMetadataCodec.authenticatedHeader(for: metadata)
            )
        } catch {
            throw VaultKeyEnvelopeError.authenticationFailed
        }
    }
}
