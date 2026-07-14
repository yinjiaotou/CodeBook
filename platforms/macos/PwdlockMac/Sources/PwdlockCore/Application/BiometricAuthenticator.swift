import Foundation
@preconcurrency import LocalAuthentication

public enum BiometricAuthenticationResult: Equatable, Sendable {
    case success
    case cancelled
    case failed
}

public final class BiometricAuthenticationContext: @unchecked Sendable {
    public let localAuthenticationContext: LAContext

    public init(localAuthenticationContext: LAContext) {
        self.localAuthenticationContext = localAuthenticationContext
    }
}

public protocol BiometricAuthenticating: AnyObject, Sendable {
    var isTouchIDAvailable: Bool { get }
    func authenticate(
        reason: String,
        completion: @escaping @Sendable (BiometricAuthenticationResult, BiometricAuthenticationContext?) -> Void
    )
    func cancel()
}

public final class LocalAuthenticationAuthenticator: BiometricAuthenticating, @unchecked Sendable {
    private let contextLock = NSLock()
    private var currentContext: LAContext?

    public init() {}

    public var isTouchIDAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
            && context.biometryType == .touchID
    }

    public func authenticate(
        reason: String,
        completion: @escaping @Sendable (BiometricAuthenticationResult, BiometricAuthenticationContext?) -> Void
    ) {
        let context = LAContext()
        var evaluationError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &evaluationError),
              context.biometryType == .touchID else {
            completion(.failed, nil)
            return
        }

        replaceCurrentContext(with: context)
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) {
            [weak self] success, error in
            self?.clearCurrentContext(ifSameAs: context)
            if success {
                completion(
                    .success,
                    BiometricAuthenticationContext(localAuthenticationContext: context)
                )
            } else if Self.isCancellation(error) {
                completion(.cancelled, nil)
            } else {
                completion(.failed, nil)
            }
        }
    }

    public func cancel() {
        let context: LAContext? = contextLock.withLock {
            defer { currentContext = nil }
            return currentContext
        }
        context?.invalidate()
    }

    private func replaceCurrentContext(with context: LAContext) {
        let previous: LAContext? = contextLock.withLock {
            defer { currentContext = context }
            return currentContext
        }
        previous?.invalidate()
    }

    private func clearCurrentContext(ifSameAs context: LAContext) {
        contextLock.withLock {
            if currentContext === context {
                currentContext = nil
            }
        }
    }

    private static func isCancellation(_ error: Error?) -> Bool {
        guard let code = (error as? LAError)?.code else { return false }
        return code == .userCancel || code == .appCancel || code == .systemCancel
    }
}
