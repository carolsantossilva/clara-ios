import SwiftUI

@main
struct ClaraApp: App {
    // Created only once: it is the "composition root", where the real dependencies are wired.
    @State private var environment = AppEnvironment.make()

    var body: some Scene {
        WindowGroup {
            RootView(environment: environment)
        }
    }
}
