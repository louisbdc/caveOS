import SwiftUI

@main
struct CaveOSWatchApp: App {
    @State private var session = WatchSessionManager()

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environment(session)
        }
    }
}
