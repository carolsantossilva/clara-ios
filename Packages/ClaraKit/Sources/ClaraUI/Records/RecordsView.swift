import ClaraCore
import SwiftUI

public struct RecordsView: View {
    @Bindable var viewModel: RecordsViewModel
    @State private var sheet: FormSheet?
    @State private var pendingDeletion: Moment?

    private struct FormSheet: Identifiable {
        let id = UUID()
        let draft: MomentDraft
        let original: Moment?
    }

    public init(viewModel: RecordsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ClaraSpacing.large) {
                PageHeading(
                    eyebrow: "Seus registros, do seu jeito",
                    title: "Como você tem estado?",
                    subtitle: "Anote só o que fizer sentido para você."
                )
                recordButton(
                    "Check-in de hoje",
                    subtitle: "Uma palavra já basta. Também pode pular.",
                    symbol: "sun.max",
                    kind: .daily,
                    identifier: "records.checkIn"
                )
                recordButton(
                    "Registrar um momento",
                    subtitle: "Bom, difícil ou algo que queira lembrar.",
                    symbol: "sparkle",
                    kind: .event,
                    identifier: "records.newMoment"
                )
                Text("O que você escolheu guardar")
                    .font(ClaraFont.headline)
                    .accessibilityAddTraits(.isHeader)
                if viewModel.isLoading {
                    ProgressView("Abrindo seus registros…")
                } else if viewModel.moments.isEmpty {
                    Text("☁\nAqui aparecem só os momentos que você decidir guardar.")
                        .font(.footnote)
                        .foregroundStyle(ClaraColor.muted)
                        .frame(maxWidth: .infinity, minHeight: 100)
                        .multilineTextAlignment(.center)
                } else {
                    ForEach(viewModel.moments) { moment in
                        MomentRow(moment: moment, onEdit: { edit(moment) }, onDelete: { pendingDeletion = moment })
                    }
                }
            }
            .padding(.top, ClaraSpacing.medium)
            .padding(.horizontal, ClaraSpacing.large)
            .padding(.bottom, ClaraSpacing.extraLarge)
        }
        .foregroundStyle(ClaraColor.ink)
        .background(ClaraColor.background.ignoresSafeArea())
        .accessibilityIdentifier("records.timeline")
        .task { await viewModel.load() }
        .claraAlert($viewModel.alert)
        .sheet(item: $sheet) { form in
            MomentFormView(
                draft: form.draft,
                isEditing: form.original != nil,
                maximumDate: viewModel.newDraft(kind: .event).occurredAt,
                onSave: { draft in
                    let result = await viewModel.save(draft, editing: form.original)
                    if result == .saved { sheet = nil }
                    return result
                },
                onClose: { sheet = nil }
            )
        }
        .alert("Excluir este registro?", isPresented: Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        ), presenting: pendingDeletion) { moment in
            Button("Excluir", role: .destructive) {
                pendingDeletion = nil
                Task { await viewModel.delete(moment) }
            }
            Button("Manter", role: .cancel) { pendingDeletion = nil }
        } message: { _ in
            Text("Ele será removido deste aparelho.")
        }
    }

    private func edit(_ moment: Moment) {
        sheet = FormSheet(draft: MomentDraft(editing: moment), original: moment)
    }

    private func recordButton(
        _ title: String,
        subtitle: String,
        symbol: String,
        kind: Moment.Kind,
        identifier: String
    ) -> some View {
        Button {
            sheet = FormSheet(draft: viewModel.newDraft(kind: kind), original: nil)
        } label: {
            HStack(spacing: ClaraSpacing.medium) {
                Image(systemName: symbol).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.bold())
                    Text(subtitle).font(.footnote).foregroundStyle(ClaraColor.muted)
                }
                Spacer(minLength: 0)
            }
            .multilineTextAlignment(.leading)
            .claraCard(background: kind == .daily ? ClaraColor.sunshine : ClaraColor.lavender)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

struct MomentRow: View {
    let moment: Moment
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ClaraSpacing.small) {
            VStack(alignment: .leading, spacing: 4) {
                moodLabel
                dateLabel
            }
            if !moment.note.isEmpty { Text(moment.note).font(.subheadline) }
            if !moment.context.isEmpty { Text("Contexto: \(moment.context)").font(.subheadline) }
            if !moment.helpedOrHindered.isEmpty { Text("Ajudou ou atrapalhou: \(moment.helpedOrHindered)").font(.subheadline) }
            if !moment.hasWrittenDetails {
                Text("Só a palavra escolhida — e tudo bem.").font(.footnote).foregroundStyle(ClaraColor.muted)
            }
            HStack(spacing: ClaraSpacing.large) {
                Button(action: onEdit) { Text("Editar").frame(minWidth: 44, minHeight: 44) }
                Button(action: onDelete) { Text("Excluir").frame(minWidth: 44, minHeight: 44) }
            }
            .font(.footnote.weight(.bold))
            .tint(ClaraColor.lavenderDeep)
            .buttonStyle(.borderless)
            .frame(minHeight: 44)
        }
        .claraCard()
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Editar", onEdit)
        .accessibilityAction(named: "Excluir", onDelete)
        .accessibilityIdentifier("records.row")
    }

    private var moodLabel: some View {
        Text("\(moment.mood?.symbol ?? "♡") \(moment.mood?.label ?? "sem descrição")")
            .font(.footnote.weight(.bold))
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(ClaraColor.lavenderDeep)
            .padding(6)
            .background(ClaraColor.lavender, in: RoundedRectangle(cornerRadius: 10))
    }

    private var dateLabel: some View {
        Text("\(moment.kind == .daily ? "Check-in" : "Momento") · \(ClaraFormat.dateTime(moment.occurredAt, in: moment.timeZone))")
            .font(.footnote)
            .foregroundStyle(ClaraColor.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
