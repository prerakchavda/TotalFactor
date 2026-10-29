import SwiftUI

@main
struct TotalFactorWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = WatchStore()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(store)
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        store.reconcileRestTimerTicker()
                        store.requestFreshSync()
                    }
                }
        }
    }
}
