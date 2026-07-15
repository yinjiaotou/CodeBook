import CryptoKit
import Darwin
import Foundation

public enum BiometricVaultEnvelopeError: Error, Equatable {
    case invalidEnvelope
    case authenticationFailed
    case persistenceFailed
}

public enum BiometricVaultEnvelope {
    public static let byteCount = 84

    private static let headerByteCount = 36
    private static let nonceByteCount = 12
    private static let ciphertextByteCount = 32
    private static let tagByteCount = 16
    private static let magic = Data("PWLB".utf8)

    public static func seal(
        vaultKey: Data,
        wrappingKey: Data,
        vaultID: UUID,
        nonce: Data
    ) throws -> Data {
        guard vaultKey.count == ciphertextByteCount,
              wrappingKey.count == 32,
              nonce.count == nonceByteCount else {
            throw BiometricVaultEnvelopeError.invalidEnvelope
        }

        var header = Data()
        header.append(magic)
        header.append(1)
        header.append(contentsOf: [0, 0, 0])
        header.append(uuidBytes(vaultID))
        header.append(nonce)
        guard header.count == headerByteCount else {
            throw BiometricVaultEnvelopeError.invalidEnvelope
        }

        do {
            let sealed = try AES.GCM.seal(
                vaultKey,
                using: SymmetricKey(data: wrappingKey),
                nonce: AES.GCM.Nonce(data: nonce),
                authenticating: header
            )
            var envelope = header
            envelope.append(sealed.ciphertext)
            envelope.append(sealed.tag)
            guard envelope.count == byteCount else {
                throw BiometricVaultEnvelopeError.invalidEnvelope
            }
            return envelope
        } catch let error as BiometricVaultEnvelopeError {
            throw error
        } catch {
            throw BiometricVaultEnvelopeError.authenticationFailed
        }
    }

    public static func open(
        _ data: Data,
        wrappingKey: Data,
        expectedVaultID: UUID
    ) throws -> Data {
        guard data.count == byteCount,
              wrappingKey.count == 32,
              data.prefix(4) == magic,
              data[4] == 1,
              data[5] == 0,
              data[6] == 0,
              data[7] == 0,
              Data(data[8..<24]) == uuidBytes(expectedVaultID) else {
            throw BiometricVaultEnvelopeError.invalidEnvelope
        }

        let header = Data(data[0..<headerByteCount])
        let nonce = Data(data[24..<36])
        let ciphertext = Data(data[36..<68])
        let tag = Data(data[68..<84])
        do {
            let sealed = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: nonce),
                ciphertext: ciphertext,
                tag: tag
            )
            let vaultKey = try AES.GCM.open(
                sealed,
                using: SymmetricKey(data: wrappingKey),
                authenticating: header
            )
            guard vaultKey.count == ciphertextByteCount else {
                throw BiometricVaultEnvelopeError.invalidEnvelope
            }
            return vaultKey
        } catch let error as BiometricVaultEnvelopeError {
            throw error
        } catch {
            throw BiometricVaultEnvelopeError.authenticationFailed
        }
    }

    public static func saveAtomically(_ data: Data, to url: URL) throws {
        guard data.count == byteCount else {
            throw BiometricVaultEnvelopeError.invalidEnvelope
        }

        let directory = url.deletingLastPathComponent()
        let temporaryURL = directory.appendingPathComponent(
            ".\(url.lastPathComponent).\(UUID().uuidString).tmp",
            isDirectory: false
        )
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        do {
            guard FileManager.default.createFile(
                atPath: temporaryURL.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            ) else {
                throw BiometricVaultEnvelopeError.persistenceFailed
            }
            try { () throws -> Void in
                let handle = try FileHandle(forWritingTo: temporaryURL)
                defer { try? handle.close() }
                try handle.write(contentsOf: data)
                try handle.synchronize()
            }()

            let renameStatus = temporaryURL.path.withCString { sourcePath in
                url.path.withCString { destinationPath in
                    rename(sourcePath, destinationPath)
                }
            }
            guard renameStatus == 0 else {
                throw BiometricVaultEnvelopeError.persistenceFailed
            }

            let directoryDescriptor = directory.path.withCString { Darwin.open($0, O_RDONLY) }
            guard directoryDescriptor >= 0 else {
                throw BiometricVaultEnvelopeError.persistenceFailed
            }
            defer { _ = Darwin.close(directoryDescriptor) }
            guard fsync(directoryDescriptor) == 0 else {
                throw BiometricVaultEnvelopeError.persistenceFailed
            }
        } catch let error as BiometricVaultEnvelopeError {
            throw error
        } catch {
            throw BiometricVaultEnvelopeError.persistenceFailed
        }
    }

    private static func uuidBytes(_ uuid: UUID) -> Data {
        var raw = uuid.uuid
        return withUnsafeBytes(of: &raw) { Data($0) }
    }
}
