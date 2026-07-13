@preconcurrency import AppKit
import Foundation
import PwdlockCore

final class PasteboardClipboard: Clipboard {
    var changeCount: Int {
        NSPasteboard.general.changeCount
    }

    func write(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func clear() {
        NSPasteboard.general.clearContents()
    }
}

final class MainQueueScheduler: ClipboardScheduler, VaultLockScheduler {
    func schedule(after delay: TimeInterval, action: @escaping () -> Void) {
        let scheduledAction = ScheduledAction(action)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            scheduledAction.action()
        }
    }
}

private final class ScheduledAction: @unchecked Sendable {
    let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }
}
