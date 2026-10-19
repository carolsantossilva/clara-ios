import ClaraCore
import ClaraDesignSystem
import SwiftUI

public struct ConsultationView: View {
    @Bindable var viewModel: ConsultationViewModel

    public init(viewModel: ConsultationViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ClaraSpacing.large) {
                PageHeading(
                    eyebrow: "Você escolhe o que levar",
                    title: "Preparar uma consulta",
                    subtitle: "Um resumo fiel às suas palavras, sem tirar conclusões por você."
                )
                selectionCard
                if viewModel.isPreviewing {
                    ReportPreview(viewModel: viewModel)
                }
            }
            .padding(.horizontal, ClaraSpacing.large)
            .padding(.bottom, ClaraSpacing.extraLarge)
        }
        .background(ClaraColor.background.ignoresSafeArea())
        // Recarrega sempre que a aba aparece: registros podem ter mudado na outra aba.
        .task { await viewModel.load() }
        .claraAlert($viewModel.alert)
    }

    private var selectionCard: some View {
        VStack(alignment: .leading, spacing: ClaraSpacing.large) {
            SectionHeader(eyebrow: "1 · Escolha o período", title: "De quais dias quer lembrar?")
            HStack(spacing: ClaraSpacing.small) {
                Button("Última semana", action: viewModel.chooseLastWeek)
                Button("Este mês", action: viewModel.chooseThisMonth)
            }
            .buttonStyle(.bordered)
            .tint(ClaraColor.lavenderDeep)

            DatePicker("De", selection: $viewModel.startDate, in: ...viewModel.endDate, displayedComponents: .date)
            DatePicker("Até", selection: $viewModel.endDate, in: viewModel.startDate..., displayedComponents: .date)

            SectionHeader(eyebrow: "2 · Selecione com calma", title: "O que quer incluir?") {
                Button(action: viewModel.selectAllEligible) {
                    // Área de toque mínima de 44 pt, mesmo sendo só texto.
                    Text("Selecionar tudo")
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .font(.footnote.weight(.bold))
                .tint(ClaraColor.lavenderDeep)
            }
            if viewModel.eligible.isEmpty {
                Text("Não há registros nesse período — e nenhuma data em branco vira alerta.")
                    .font(.footnote)
                    .foregroundStyle(ClaraColor.muted)
            } else {
                ForEach(viewModel.eligible) { moment in
                    SelectableMomentRow(moment: moment, isSelected: viewModel.selectedIDs.contains(moment.id)) {
                        viewModel.toggle(moment.id)
                    }
                }
            }

            LabeledTextField(
                "3 · O que você quer conversar?",
                text: $viewModel.questions,
                placeholder: "Uma pergunta ou lembrete para você…",
                axis: .vertical
            )
            Button("Ver minha prévia →") {
                withAnimation { viewModel.isPreviewing = true }
            }
            .buttonStyle(.claraPrimary)
            .accessibilityIdentifier("consultation.preview")
        }
        .claraCard(radius: ClaraRadius.card)
    }
}

private struct SelectableMomentRow: View {
    let moment: Moment
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: ClaraSpacing.medium) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(ClaraColor.lavenderDeep)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(moment.displayLabel).font(.subheadline.weight(.bold)).foregroundStyle(ClaraColor.ink)
                    Text(detail).font(.caption).foregroundStyle(ClaraColor.muted).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isSelected ? "incluído" : "não incluído")
    }

    private var detail: String {
        let date = ClaraFormat.dateTime(moment.occurredAt, in: moment.timeZone)
        return moment.note.isEmpty ? date : "\(date) · \(moment.note)"
    }
}

/// Prévia fiel do que vai para o PDF: mesmas palavras, mesma ordem.
private struct ReportPreview: View {
    let viewModel: ConsultationViewModel

    var body: some View {
        let report = viewModel.report
        VStack(alignment: .leading, spacing: ClaraSpacing.medium) {
            HStack {
                SectionHeader(eyebrow: "Prévia do seu resumo", title: "Antes de exportar")
                Button {
                    withAnimation { viewModel.isPreviewing = false }
                } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Fechar prévia")
            }
            Divider()
            Text("Registros para consulta").font(ClaraFont.title).foregroundStyle(ClaraColor.ink)
            Text("Período: \(report.start.description) a \(report.end.description)")
                .font(.caption)
                .foregroundStyle(ClaraColor.muted)

            if report.entries.isEmpty {
                Text("Nenhum registro selecionado para este período.").font(.footnote).foregroundStyle(ClaraColor.muted)
            }
            ForEach(report.entries) { moment in
                VStack(alignment: .leading, spacing: 4) {
                    Text(ClaraFormat.dateTime(moment.occurredAt, in: moment.timeZone)).font(.caption).foregroundStyle(ClaraColor.muted)
                    Text(moment.displayLabel).font(.footnote.weight(.bold)).foregroundStyle(ClaraColor.lavenderDeep)
                    if !moment.note.isEmpty { Text(moment.note).font(.footnote) }
                    if !moment.context.isEmpty { Text("Contexto que percebi: \(moment.context)").font(.footnote) }
                    if !moment.helpedOrHindered.isEmpty { Text("Algo que ajudou ou atrapalhou: \(moment.helpedOrHindered)").font(.footnote) }
                }
                .foregroundStyle(ClaraColor.ink)
                .padding(.vertical, 6)
                Divider()
            }
            if !report.questionsAndNotes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Quero conversar sobre").font(.footnote.weight(.bold)).foregroundStyle(ClaraColor.lavenderDeep)
                    Text(report.questionsAndNotes).font(.footnote).foregroundStyle(ClaraColor.ink)
                }
                .padding(ClaraSpacing.medium)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ClaraColor.lavender, in: RoundedRectangle(cornerRadius: 12))
            }
            Text("Este resumo reúne apenas o que escolhi registrar. Não explica causas nem substitui uma avaliação profissional.")
                .font(.caption)
                .foregroundStyle(ClaraColor.muted)

            if let url = viewModel.exportedFileURL {
                ShareLink(item: url) {
                    Label("Compartilhar PDF", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.borderedProminent)
                .tint(ClaraColor.lavenderDeep)
                .accessibilityIdentifier("consultation.share")
            } else {
                Button("Preparar PDF ↗", action: viewModel.exportPDF)
                    .buttonStyle(.claraPrimary)
                    .accessibilityIdentifier("consultation.export")
            }
        }
        .claraCard(radius: ClaraRadius.card)
    }
}
