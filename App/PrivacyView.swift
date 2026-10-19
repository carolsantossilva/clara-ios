import ClaraDesignSystem
import ClaraServices
import SwiftUI

/// Privacy (for the user) and diagnostics (for the demo and the team).
/// Shows live: analytics consent, remote config source, flags,
/// A/B variant, AI availability and the latest events sent.
struct PrivacyView: View {
    let environment: AppEnvironment

    @State private var hasConsent = false
    @State private var aiAvailable: Bool?
    @State private var events: [AnalyticsEvent] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Compartilhar estatísticas de uso", isOn: $hasConsent)
                        .onChange(of: hasConsent) { _, newValue in
                            environment.hasAnalyticsConsent = newValue
                        }
                        .accessibilityIdentifier("privacy.consent")
                } header: {
                    Text("Privacidade")
                } footer: {
                    Text("""
                        Desligado por padrão. Quando ligado, envia só nomes de ações (ex.: "tarefa concluída"), \
                        nunca o que você escreve. Tarefas e registros ficam só neste aparelho.
                        """)
                }

                Section("Inteligência artificial") {
                    LabeledContent("IA no aparelho") {
                        switch aiAvailable {
                        case .none: ProgressView()
                        case .some(true): Text("Disponível")
                        case .some(false): Text("Indisponível — usando sugestões simples")
                        }
                    }
                }

                Section {
                    LabeledContent("Origem da configuração", value: environment.flags.source.rawValue)
                    LabeledContent("Variante foco (A/B)", value: environment.flags.variant(.focusDuration).map { "\($0) min" } ?? "—")
                    ForEach(FeatureFlag.allCases, id: \.self) { flag in
                        Toggle(flag.rawValue, isOn: binding(for: flag))
                            .font(.footnote.monospaced())
                    }
                } header: {
                    Text("Feature flags")
                } footer: {
                    Text("Alterar aqui cria uma sobrescrita local, com prioridade sobre o remote config.")
                }

                Section("Últimos eventos (painel local)") {
                    if events.isEmpty {
                        Text(hasConsent ? "Nenhum evento ainda." : "Ative o compartilhamento para ver eventos.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(events.reversed().enumerated()), id: \.offset) { _, event in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.name).font(.footnote.monospaced().weight(.semibold))
                            if !event.properties.isEmpty {
                                Text(event.properties.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button("Atualizar") { events = environment.analyticsBuffer.events }
                }
            }
            .navigationTitle("Privacidade e diagnóstico")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
            .task {
                hasConsent = environment.hasAnalyticsConsent
                events = environment.analyticsBuffer.events
                aiAvailable = await environment.suggester.isAvailable
            }
        }
    }

    private func binding(for flag: FeatureFlag) -> Binding<Bool> {
        Binding(
            get: { environment.flags.isEnabled(flag) },
            set: { environment.flags.overrides[flag] = $0 }
        )
    }
}
