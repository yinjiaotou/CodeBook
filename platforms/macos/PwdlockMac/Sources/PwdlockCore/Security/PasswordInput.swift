import Foundation
import Security

public enum PasswordInput {
    public static func utf8NFC(_ password: String) -> Data {
        Data(password.precomposedStringWithCanonicalMapping.utf8)
    }
}

public enum SecureRandomError: Error, Equatable {
    case generationFailed(OSStatus)
}

public enum SecureRandom {
    public static func bytes(count: Int) throws -> Data {
        var bytes = Data(repeating: 0, count: count)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw SecureRandomError.generationFailed(status)
        }
        return bytes
    }
}
