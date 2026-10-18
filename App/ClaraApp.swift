import SwiftUI

@main
struct ClaraApp: App {
    // Criado uma única vez: é o "composition root", onde as dependências reais são montadas.
    @State private var environment = AppEnvironment.make()

    var body: some Scene {
        WindowGroup {
            RootView(environment: environment)
                .task { await environment.bootstrap() }
        }
    }
}
