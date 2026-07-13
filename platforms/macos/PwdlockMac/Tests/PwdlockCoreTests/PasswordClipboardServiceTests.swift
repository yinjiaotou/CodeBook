import Foundation
import Testing
@testable import PwdlockCore

@Test("copied password is cleared after thirty seconds")
func clearsCopiedPassword() {
    let clipboard = InMemoryClipboard()
    let scheduler = ManualClipboardScheduler()
    let service = PasswordClipboardService(clipboard: clipboard, scheduler: scheduler)

    service.copy(password: "secret")

    #expect(clipboard.text == "secret")
    #expect(scheduler.delay == 30)
    scheduler.fire()
    #expect(clipboard.text == nil)
}

@Test("clipboard cleanup does not overwrite a newer user copy")
func preservesNewerClipboardContent() {
    let clipboard = InMemoryClipboard()
    let scheduler = ManualClipboardScheduler()
    let service = PasswordClipboardService(clipboard: clipboard, scheduler: scheduler)

    service.copy(password: "secret")
    clipboard.write("user copied this")
    scheduler.fire()

    #expect(clipboard.text == "user copied this")
}

private final class InMemoryClipboard: Clipboard {
    private(set) var text: String?
    private(set) var changeCount = 0

    func write(_ text: String) {
        self.text = text
        changeCount += 1
    }

    func clear() {
        text = nil
        changeCount += 1
    }
}

private final class ManualClipboardScheduler: ClipboardScheduler {
    private(set) var delay: TimeInterval?
    private var action: (() -> Void)?

    func schedule(after delay: TimeInterval, action: @escaping () -> Void) {
        self.delay = delay
        self.action = action
    }

    func fire() {
        action?()
    }
}
