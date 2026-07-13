import Foundation

public protocol VaultLockScheduler: AnyObject {
    func schedule(after delay: TimeInterval, action: @escaping () -> Void)
}

public final class VaultAutoLockController {
    private let session: VaultSession
    private let scheduler: VaultLockScheduler
    private var timeout: TimeInterval
    private let onLock: () -> Void
    private var latestActivityToken = UUID()

    public init(
        session: VaultSession,
        scheduler: VaultLockScheduler,
        timeout: TimeInterval,
        onLock: @escaping () -> Void = {}
    ) {
        self.session = session
        self.scheduler = scheduler
        self.timeout = timeout
        self.onLock = onLock
    }

    public func recordActivity() {
        guard session.isUnlocked else { return }
        let token = UUID()
        latestActivityToken = token
        scheduler.schedule(after: timeout) { [weak self] in
            guard let self, self.latestActivityToken == token else { return }
            self.session.lock()
            self.onLock()
        }
    }

    public func updateTimeout(_ timeout: TimeInterval) {
        self.timeout = timeout
        latestActivityToken = UUID()
        recordActivity()
    }

    public func applicationDidEnterBackground() {
        guard session.isUnlocked else { return }
        latestActivityToken = UUID()
        session.lock()
        onLock()
    }
}
