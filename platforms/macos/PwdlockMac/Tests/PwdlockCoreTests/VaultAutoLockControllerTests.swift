import Foundation
import Testing
@testable import PwdlockCore

@Test("auto-lock controller locks an unlocked vault after configured inactivity")
func locksAfterInactivity() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let session = VaultSession(directory: directory)
    try session.create(masterPassword: "correct horse battery staple")
    let scheduler = ManualLockScheduler()
    let controller = VaultAutoLockController(session: session, scheduler: scheduler, timeout: 180)

    controller.recordActivity()
    scheduler.fire()

    #expect(!session.isUnlocked)
}

@Test("background transition locks the vault immediately")
func locksOnBackgroundTransition() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let session = VaultSession(directory: directory)
    try session.create(masterPassword: "correct horse battery staple")
    let controller = VaultAutoLockController(session: session, scheduler: ManualLockScheduler(), timeout: 180)

    controller.applicationDidEnterBackground()

    #expect(!session.isUnlocked)
}

@Test("changing the timeout replaces an existing inactivity schedule")
func timeoutChangeReplacesExistingSchedule() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let session = VaultSession(directory: directory)
    try session.create(masterPassword: "correct horse battery staple")
    let scheduler = ManualLockScheduler()
    let controller = VaultAutoLockController(session: session, scheduler: scheduler, timeout: 300)

    controller.recordActivity()
    controller.updateTimeout(600)

    #expect(scheduler.delays == [300, 600])

    scheduler.fire(at: 0)
    #expect(session.isUnlocked)

    scheduler.fire(at: 1)
    #expect(!session.isUnlocked)
}

private final class ManualLockScheduler: VaultLockScheduler {
    private var actions: [() -> Void] = []
    private(set) var delays: [TimeInterval] = []

    func schedule(after delay: TimeInterval, action: @escaping () -> Void) {
        delays.append(delay)
        actions.append(action)
    }

    func fire() {
        actions.last?()
    }

    func fire(at index: Int) {
        actions[index]()
    }
}
