import Foundation

public protocol Clipboard: AnyObject {
    var changeCount: Int { get }
    func write(_ text: String)
    func clear()
}

public protocol ClipboardScheduler: AnyObject {
    func schedule(after delay: TimeInterval, action: @escaping () -> Void)
}

public final class PasswordClipboardService {
    public static let automaticClearDelay: TimeInterval = 30

    private let clipboard: Clipboard
    private let scheduler: ClipboardScheduler
    private var copiedChangeCount: Int?

    public init(clipboard: Clipboard, scheduler: ClipboardScheduler) {
        self.clipboard = clipboard
        self.scheduler = scheduler
    }

    public func copy(password: String) {
        clipboard.write(password)
        let expectedChangeCount = clipboard.changeCount
        copiedChangeCount = expectedChangeCount
        scheduler.schedule(after: Self.automaticClearDelay) { [weak self] in
            self?.clearIfUnchanged(expectedChangeCount: expectedChangeCount)
        }
    }

    public func clearNow() {
        guard let expectedChangeCount = copiedChangeCount else { return }
        clearIfUnchanged(expectedChangeCount: expectedChangeCount)
    }

    private func clearIfUnchanged(expectedChangeCount: Int) {
        guard copiedChangeCount == expectedChangeCount else { return }
        guard clipboard.changeCount == expectedChangeCount else {
            copiedChangeCount = nil
            return
        }
        clipboard.clear()
        copiedChangeCount = nil
    }
}
