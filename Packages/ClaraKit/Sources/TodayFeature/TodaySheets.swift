import ClaraAI
import ClaraCore
import ClaraDesignSystem
import SwiftUI

/// "Tire uma coisa da cabeça" (get one thing off your mind): creates a task.
/// The fields are `@State` because they are the sheet's local draft, not app state.
struct AddTaskSheet: View {
    let viewModel: TodayViewModel
    @State private var title = ""
    @State private var nextAction = ""
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ClaraSpacing.large) {
                    LabeledTextField(
                        "O que você quer fazer?",
                        text: $title,
                        placeholder: "ex.: responder a mensagem da clínica",
                        isOptional: false,
                        identifier: "addTask.title"
                    )
                    LabeledTextField(
                        "Qual é o primeiro passo?",
                        text: $nextAction,
                        placeholder: "ex.: abrir a conversa",
                        identifier: "addTask.nextAction"
                    )
                    Button("Salvar tarefa") {
                        isSaving = true
                        Task {
                            await viewModel.createTask(title: title, nextAction: nextAction)
                            isSaving = false
                        }
                    }
                    .buttonStyle(.claraPrimary)
                    .disabled(title.trimmed.isEmpty || isSaving)
                    .accessibilityIdentifier("addTask.save")
                }
                .padding(ClaraSpacing.large)
            }
            .background(ClaraColor.background)
            .navigationTitle("Tire uma coisa da cabeça")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Agora não") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// "Deixe uma pista para você" (leave yourself a hint): saves where she stopped and the next step.
struct PauseSheet: View {
    let task: FocusTask
    let viewModel: TodayViewModel
    @State private var whereStopped = ""
    @State private var nextStep = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ClaraSpacing.large) {
                    Text(task.title)
                        .font(ClaraFont.title)
                        .foregroundStyle(ClaraColor.ink)
                    LabeledTextField(
                        "Onde você parou?",
                        text: $whereStopped,
                        placeholder: "ex.: parei na parte dos documentos",
                        identifier: "pause.whereStopped"
                    )
                    LabeledTextField(
                        "Qual será o próximo passo?",
                        text: $nextStep,
                        placeholder: task.nextAction.isEmpty ? "ex.: abrir a pasta de exames" : task.nextAction
                    )
                    Button("Salvar para retomar") {
                        Task { await viewModel.pause(whereStopped: whereStopped, nextStep: nextStep) }
                    }
                    .buttonStyle(.claraPrimary)
                    .accessibilityIdentifier("pause.save")
                }
                .padding(ClaraSpacing.large)
            }
            .background(ClaraColor.background)
            .navigationTitle("Deixe uma pista para você")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Voltar") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Small-step suggestions with AI. The user picks a step, or none.
struct StepSuggestionsSheet: View {
    let viewModel: StepSuggestionsViewModel
    let onAccept: @MainActor (String, StepSuggestion.Source) async -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ClaraSpacing.large) {
                    Text("Para começar “\(viewModel.task.title)”, escolha um passo que pareça leve. Ele vira o seu próximo passo.")
                        .font(.subheadline)
                        .foregroundStyle(ClaraColor.muted)
                    content
                }
                .padding(ClaraSpacing.large)
            }
            .background(ClaraColor.background)
            .navigationTitle("Passos pequenos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Agora não") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView("Pensando em passos pequenos…")
                .frame(maxWidth: .infinity, minHeight: 120)
        case .failed:
            Text("Não foi possível sugerir agora. Tudo bem começar do seu jeito.")
                .font(.subheadline)
                .foregroundStyle(ClaraColor.ink)
        case .loaded(let suggestion):
            VStack(alignment: .leading, spacing: ClaraSpacing.small) {
                ForEach(suggestion.steps, id: \.self) { step in
                    Button {
                        Task { await onAccept(step, suggestion.source) }
                    } label: {
                        HStack {
                            Text(step).multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "arrow.up.right").accessibilityHidden(true)
                        }
                        .foregroundStyle(ClaraColor.ink)
                        .padding(ClaraSpacing.medium)
                        .frame(minHeight: 44)
                        .background(ClaraColor.paper, in: RoundedRectangle(cornerRadius: ClaraRadius.control))
                        .overlay(RoundedRectangle(cornerRadius: ClaraRadius.control).strokeBorder(ClaraColor.line))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Usar como próximo passo")
                }
                SourceBadge(source: suggestion.source)
            }
        }
    }
}

/// Transparency: shows where the suggestion came from.
private struct SourceBadge: View {
    let source: StepSuggestion.Source

    var body: some View {
        Label(text, systemImage: source == .onDevice ? "sparkles" : "text.badge.checkmark")
            .font(.caption)
            .foregroundStyle(ClaraColor.muted)
            .padding(.top, ClaraSpacing.small)
    }

    private var text: String {
        switch source {
        case .onDevice: "Gerado no aparelho pelo Apple Intelligence. Nada saiu do seu iPhone."
        case .heuristic: "Sugestões simples: a IA do aparelho não está disponível aqui."
        }
    }
}
