import ClaraDesignSystem
import ConsultationFeature
import RecordsFeature
import SwiftUI
import TodayFeature

/// Main navigation: three tabs, as in the original app.
/// Each tab is an independent feature, each with the architecture that made sense.
struct RootView: View {
    let environment: AppEnvironment

    enum Tab: Hashable {
        case today
        case records
        case consultation
    }

    @State private var selection: Tab = .today

    var body: some View {
        TabView(selection: $selection) {
            // SwiftUI + MVVM-C
            TodayCoordinatorView(coordinator: environment.todayCoordinator)
                .tabItem { Label("Hoje", systemImage: "sun.max") }
                .tag(Tab.today)

            // UIKit (View Code) + VIP, embedded through UIViewControllerRepresentable
            RecordsScreen(dependencies: environment.recordsDependencies)
                .background(ClaraColor.background.ignoresSafeArea())
                .tabItem { Label("Registros", systemImage: "book.closed") }
                .tag(Tab.records)

            // SwiftUI + MVVM
            ConsultationView(viewModel: environment.consultationViewModel)
                .tabItem { Label("Consulta", systemImage: "doc.text") }
                .tag(Tab.consultation)
        }
        .tint(ClaraColor.lavenderDeep)
    }
}
