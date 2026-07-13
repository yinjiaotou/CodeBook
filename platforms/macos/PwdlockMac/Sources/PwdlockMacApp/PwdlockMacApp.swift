import SwiftUI

@main
struct PwdlockMacApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var state = VaultAppState()

    var body: some Scene {
        WindowGroup {
            VaultRootView(state: state)
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active {
                        state.applicationDidEnterBackground()
                    } else {
                        state.recordActivity()
                    }
                }
        }
    }
}
