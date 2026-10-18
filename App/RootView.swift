import ClaraDesignSystem
import ConsultationFeature
import RecordsFeature
import SwiftUI
import TodayFeature

/// Navegação principal: três abas, como no app original.
/// Cada aba é uma feature independente, cada uma com a arquitetura que fez sentido.
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

            // UIKit (View Code) + VIP, embutido via UIViewControllerRepresentable
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
