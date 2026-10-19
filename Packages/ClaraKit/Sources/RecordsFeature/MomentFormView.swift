import ClaraCore
import ClaraDesignSystem
import SwiftUI

/// Check-in/moment form in SwiftUI, presented by the UIKit Router.
struct MomentFormView: View {
    @State var draft: MomentDraft
    let isEditing: Bool
    let maximumDate: Date
    let onSave: @MainActor (MomentDraft) async -> MomentSaveResult
    let onClose: @MainActor () -> Void

    @State private var message: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MoodPicker(selection: $draft.mood)
                        .listRowBackground(Color.clear)
                } header: {
                    Text(draft.kind == .daily ? "Como está hoje?" : "O que você percebeu?")
                }

                if draft.kind == .event {
                    Section {
                        DatePicker("Quando aconteceu?", selection: $draft.occurredAt, in: ...maximumDate)
                            .accessibilityIdentifier("momentForm.date")
                    }
                }

                Section("Quer deixar algumas palavras? (opcional)") {
                    TextField("Escreva do seu jeito…", text: $draft.note, axis: .vertical)
                        .lineLimit(3...8)
                        .accessibilityIdentifier("momentForm.note")
                }
                Section("Contexto que você percebeu (opcional)") {
                    TextField("ex.: depois de uma noite curta", text: $draft.context)
                }
                Section {
                    TextField("ex.: caminhar um pouco ajudou", text: $draft.helpedOrHindered)
                } header: {
                    Text("Algo ajudou ou atrapalhou? (opcional)")
                } footer: {
                    Text("Contexto e o que ajudou ou atrapalhou são observações suas. O Clara não tira conclusões sobre causas.")
                }

                if let message {
                    Section {
                        Text(message)
                            .foregroundStyle(ClaraColor.lavenderDeep)
                            .accessibilityIdentifier("momentForm.message")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ClaraColor.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Deixar para depois", action: onClose)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar", action: save)
                        .disabled(isSaving)
                        .accessibilityIdentifier("momentForm.save")
                }
            }
        }
    }

    private var title: String {
        if isEditing { return "Editar registro" }
        return draft.kind == .daily ? "Check-in opcional" : "Um momento seu"
    }

    private func save() {
        isSaving = true
        Task {
            let result = await onSave(draft)
            isSaving = false
            switch result {
            case .saved:
                message = nil
            case .needsContent:
                message = "Quer guardar o quê? Escolha uma palavra ou escreva qualquer detalhe. Também pode deixar para depois."
            case .failed:
                message = "Não foi possível salvar. Tente novamente em instantes."
            }
        }
    }
}
