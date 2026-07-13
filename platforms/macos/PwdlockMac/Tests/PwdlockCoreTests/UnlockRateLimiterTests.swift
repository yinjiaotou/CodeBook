import Foundation
import Testing
@testable import PwdlockCore

@Test("five consecutive failed unlocks start a 30-second cooldown that expires with the injected clock")
func fiveFailuresStartThirtySecondCooldown() {
    let clock = UnlockTestClock(now: Date(timeIntervalSince1970: 1_760_000_000))
    let limiter = UnlockRateLimiter(now: { clock.now })

    for _ in 0..<4 {
        limiter.recordFailedUnlock()
    }
    #expect(!limiter.isCoolingDown)

    limiter.recordFailedUnlock()
    #expect(limiter.isCoolingDown)

    clock.advance(by: 29)
    #expect(limiter.isCoolingDown)

    clock.advance(by: 1)
    #expect(!limiter.isCoolingDown)
}

@Test("success resets failed unlock cooldown escalation")
func successfulUnlockResetsCooldownEscalation() {
    let clock = UnlockTestClock(now: Date(timeIntervalSince1970: 1_760_000_000))
    let limiter = UnlockRateLimiter(now: { clock.now })

    for _ in 0..<5 {
        limiter.recordFailedUnlock()
    }
    clock.advance(by: 30)
    limiter.recordSuccessfulUnlock()

    for _ in 0..<5 {
        limiter.recordFailedUnlock()
    }
    clock.advance(by: 29)
    #expect(limiter.isCoolingDown)

    clock.advance(by: 1)
    #expect(!limiter.isCoolingDown)
}

@Test("repeated groups of failed unlocks escalate cooldowns and cap at five minutes")
func failedUnlockCooldownsEscalateAndCap() {
    let clock = UnlockTestClock(now: Date(timeIntervalSince1970: 1_760_000_000))
    let limiter = UnlockRateLimiter(now: { clock.now })

    for duration in [30.0, 60.0, 120.0, 300.0, 300.0] {
        for _ in 0..<5 {
            limiter.recordFailedUnlock()
        }
        #expect(limiter.isCoolingDown)

        clock.advance(by: duration - 1)
        #expect(limiter.isCoolingDown)

        clock.advance(by: 1)
        #expect(!limiter.isCoolingDown)
    }
}

private final class UnlockTestClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }

    func advance(by interval: TimeInterval) {
        now.addTimeInterval(interval)
    }
}
