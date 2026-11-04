import SwiftUI

@main
struct KalamApp: App {
    @State private var store = StoreHolder()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(store)
                // An idle WAL connection holds a lock on -shm; suspending with it gets the app killed (0xdead10cc).
                .onChange(of: scenePhase, initial: true) { _, phase in
                    if phase == .active { store.open() } else if phase == .background { store.close() }
                }
        }
    }
}
