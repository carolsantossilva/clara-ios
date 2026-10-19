import ClaraUI
import SwiftUI

struct RootView: View {
    let environment: AppEnvironment
    @State private var storageWarning: AlertContent?

    var body: some View {
        TabView {
            TodayView(viewModel: environment.todayViewModel) {
                PrivacyView(environment: environment)
            }
            .tabItem { Label("Hoje", systemImage: "sun.max") }

            RecordsView(viewModel: environment.recordsViewModel)
                .tabItem { Label("Registros", systemImage: "book.closed") }

            ConsultationView(viewModel: environment.consultationViewModel)
                .tabItem { Label("Consulta", systemImage: "doc.text") }
        }
        .tint(ClaraColor.lavenderDeep)
        .onAppear { storageWarning = environment.storageWarning }
        .claraAlert($storageWarning)
    }
}
