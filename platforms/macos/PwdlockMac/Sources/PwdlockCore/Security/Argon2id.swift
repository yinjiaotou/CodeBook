import CArgon2
import Foundation

public struct Argon2idParameters: Sendable, Equatable {
    public let memoryKiB: UInt32
    public let iterations: UInt32
    public let parallelism: UInt32

    public init(memoryKiB: UInt32, iterations: UInt32, parallelism: UInt32) {
        self.memoryKiB = memoryKiB
        self.iterations = iterations
        self.parallelism = parallelism
    }

    public static let initial = Argon2idParameters(memoryKiB: 65_536, iterations: 3, parallelism: 1)
}

public enum Argon2idError: Error, Equatable {
    case invalidInput
    case derivationFailed(Int32)
}

public enum Argon2id {
    public static func deriveKey(
        password: Data,
        salt: Data,
        parameters: Argon2idParameters
    ) throws -> Data {
        guard !password.isEmpty,
              salt.count >= 8,
              parameters.memoryKiB > 0,
              parameters.iterations > 0,
              parameters.parallelism > 0 else {
            throw Argon2idError.invalidInput
        }

        var output = Data(repeating: 0, count: 32)
        let status = output.withUnsafeMutableBytes { outputBuffer in
            password.withUnsafeBytes { passwordBuffer in
                salt.withUnsafeBytes { saltBuffer in
                    argon2id_hash_raw(
                        parameters.iterations,
                        parameters.memoryKiB,
                        parameters.parallelism,
                        passwordBuffer.baseAddress,
                        passwordBuffer.count,
                        saltBuffer.baseAddress,
                        saltBuffer.count,
                        outputBuffer.baseAddress,
                        outputBuffer.count
                    )
                }
            }
        }
        guard status == ARGON2_OK.rawValue else {
            throw Argon2idError.derivationFailed(status)
        }
        return output
    }
}
