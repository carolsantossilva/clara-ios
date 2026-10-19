import ClaraUI
import SwiftUI

struct PrivacyView: View {
    let environment: AppEnvironment
    @State private var hasConsent = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Registrar estatísticas locais de uso", isOn: $hasConsent)
                        .onChange(of: hasConsent) { _, newValue in environment.hasAnalyticsConsent = newValue }
                        .accessibilityIdentifier("privacy.consent")
                } header: {
                    Text("Privacidade")
                } footer: {
                    Text("Desligado por padrão. Quando ligado, registra ações e contagens neste aparelho, sem o conteúdo de tarefas ou registros.")
                }
                Section("Seus dados") {
                    Text("Tarefas e registros ficam neste aparelho. Ao compartilhar um PDF, você escolhe com quem enviar o resumo.")
                }
                Section("Sugestões de passos") {
                    Text("""
                        A IA funciona no aparelho, quando disponível. Caso contrário, o app oferece sugestões simples. \
                        A origem aparece junto de cada sugestão.
                        """)
                }
            }
            .navigationTitle("Privacidade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
            .onAppear { hasConsent = environment.hasAnalyticsConsent }
        }
    }
}
