import AppKit
import SwiftUI

@main
struct PwdlockMacApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @NSApplicationDelegateAdaptor(PwdlockAppDelegate.self) private var appDelegate
    @StateObject private var state = VaultAppState()

    var body: some Scene {
        WindowGroup {
            PasswordModeRootView(localState: state)
                .onAppear {
                    appDelegate.onDidResignActive = { [weak state] in
                        state?.applicationDidResignActive()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active {
                        state.applicationDidResignActive()
                    } else {
                        state.recordActivity()
                    }
                }
        }
    }
}

enum PasswordStorageMode: String {
    case local
    case online
}

/// Keeps the two vault experiences separate: the offline state never has to
/// know about account sessions, while the online state never opens local files.
private struct PasswordModeRootView: View {
    @ObservedObject var localState: VaultAppState
    @AppStorage("passwordStorageMode") private var persistedMode = ""

    private var selectedMode: PasswordStorageMode? {
        PasswordStorageMode(rawValue: persistedMode)
    }

    var body: some View {
        Group {
            switch selectedMode {
            case .local:
                VaultRootView(state: localState)
            case .online:
                OnlineVaultRootView(switchToMode: switchToMode)
            case nil:
                PasswordModeSelectionView(selectMode: switchToMode)
            }
        }
    }

    private func switchToMode(_ mode: PasswordStorageMode) {
        persistedMode = mode.rawValue
    }
}

private final class PwdlockAppDelegate: NSObject, NSApplicationDelegate {
    var onDidResignActive: (() -> Void)?

    func applicationDidResignActive(_ notification: Notification) {
        onDidResignActive?()
    }
}
