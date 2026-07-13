import Foundation

public final class UnlockRateLimiter {
    private static let failuresPerCooldown = 5
    private static let cooldownDurations: [TimeInterval] = [30, 60, 120, 300]

    private let now: () -> Date
    private var failedUnlockCount = 0
    private var cooldownCount = 0
    private var cooldownEndsAt: Date?

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    public var isCoolingDown: Bool {
        guard let cooldownEndsAt else { return false }
        return now() < cooldownEndsAt
    }

    public func recordFailedUnlock() {
        guard !isCoolingDown else { return }

        failedUnlockCount += 1
        guard failedUnlockCount.isMultiple(of: Self.failuresPerCooldown) else { return }

        let index = min(cooldownCount, Self.cooldownDurations.count - 1)
        cooldownEndsAt = now().addingTimeInterval(Self.cooldownDurations[index])
        cooldownCount += 1
    }

    public func recordSuccessfulUnlock() {
        failedUnlockCount = 0
        cooldownCount = 0
        cooldownEndsAt = nil
    }
}
