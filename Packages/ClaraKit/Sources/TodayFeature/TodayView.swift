import ClaraCore
import ClaraDesignSystem
import ClaraServices
import SwiftUI

/// Tela Hoje. Views em SwiftUI são *descrições* baratas da interface: o `body`
/// pode ser recalculado muitas vezes, por isso não guardamos estado nelas — ele
/// fica no ViewModel (`@Observable`) ou em `@State` para coisas locais da view.
struct TodayView: View {
    // `@Bindable` permite criar bindings (`$viewModel.parkingText`) para um objeto @Observable.
    @Bindable var viewModel: TodayViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ClaraSpacing.large) {
                BrandHeader {
                    Button(action: viewModel.privacyTapped) { LocalOnlyBadge() }
                        .accessibilityHint("Abre privacidade e diagnóstico")
                        .accessibilityIdentifier("today.privacyBadge")
                }
                PageHeading(
                    eyebrow: "Seu cantinho de hoje",
                    title: "Um passo de cada vez ✳",
                    subtitle: "O que cabe agora já é suficiente."
                )
                if let holiday = viewModel.upcomingHoliday {
                    HolidayBanner(holiday: holiday)
                }
                FocusSection(viewModel: viewModel)
                OtherTasksSection(viewModel: viewModel)
                ParkingSection(viewModel: viewModel)
                Text("☁  Você pode começar pelo que está mais perto.")
                    .font(.caption)
                    .foregroundStyle(ClaraColor.muted)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, ClaraSpacing.large)
            .padding(.bottom, ClaraSpacing.extraLarge)
        }
        .background(ClaraColor.background.ignoresSafeArea())
        // `.task` começa quando a view aparece e é cancelada quando ela some.
        .task { await viewModel.onAppear() }
        .claraAlert($viewModel.alert)
    }
}

// MARK: - Foco

private struct FocusSection: View {
    let viewModel: TodayViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: ClaraSpacing.medium) {
            if viewModel.isLoading {
                ProgressView("Abrindo seu espaço…")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if let focus = viewModel.focus {
                TaskCard(task: focus)
                FocusActions(viewModel: viewModel)
            } else {
                EmptyStateView()
                Button("Adicionar uma tarefa ＋", action: viewModel.addTaskTapped)
                    .buttonStyle(.claraPrimary)
                    .accessibilityIdentifier("today.addFirstTask")
            }
        }
        .claraCard(background: ClaraColor.lavender.opacity(0.5), radius: ClaraRadius.card)
    }
}

private struct TaskCard: View {
    let task: FocusTask

    var body: some View {
        VStack(alignment: .leading, spacing: ClaraSpacing.medium) {
            HStack {
                EyebrowText("✦  Seu próximo passo")
                Spacer()
                Text("sem pressa")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ClaraColor.sageInk)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(ClaraColor.sage, in: Capsule())
            }
            Text(task.title)
                .font(ClaraFont.largeTitle)
                .foregroundStyle(ClaraColor.ink)
                .accessibilityIdentifier("today.focusTitle")
            if task.nextAction.isEmpty {
                Text("Você pode começar descobrindo só o primeiro passo.")
                    .font(.subheadline)
                    .foregroundStyle(ClaraColor.muted)
            } else {
                Label {
                    Text(task.nextAction).foregroundStyle(ClaraColor.ink)
                } icon: {
                    Text("1")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(ClaraColor.lavenderDeep)
                        .frame(width: 24, height: 24)
                        .background(ClaraColor.lavender, in: RoundedRectangle(cornerRadius: 9))
                }
                .accessibilityLabel("Próximo passo: \(task.nextAction)")
            }
            if !task.whereStopped.isEmpty {
                Text("Você parou em: \(task.whereStopped)")
                    .font(.footnote)
                    .foregroundStyle(ClaraColor.sageInk)
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ClaraColor.sage, in: RoundedRectangle(cornerRadius: 9))
            }
        }
        .claraCard(radius: ClaraRadius.card)
    }
}

private struct FocusActions: View {
    let viewModel: TodayViewModel

    var body: some View {
        VStack(spacing: ClaraSpacing.small) {
            if viewModel.timer.isRunning {
                TimerView(timer: viewModel.timer)
            } else {
                Button("Começar por \(viewModel.focusMinutes) min →") {
                    Task { await viewModel.startFocus() }
                }
                .buttonStyle(.claraPrimary)
                .accessibilityIdentifier("today.startFocus")
            }
            Button("Pausar e salvar", action: viewModel.pauseTapped)
                .buttonStyle(.claraSecondary)
                .accessibilityIdentifier("today.pause")
            if viewModel.showsStepSuggestions {
                Button("✨ Sugerir passos pequenos", action: viewModel.suggestStepsTapped)
                    .buttonStyle(.claraSecondary)
                    .accessibilityIdentifier("today.suggestSteps")
            }
            Button("Marcar como concluída") {
                Task { await viewModel.completeFocus() }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(ClaraColor.lavenderDeep)
            .frame(minHeight: 44)
            .accessibilityIdentifier("today.complete")
        }
    }
}

/// View pequena e separada de propósito: só ela lê `remainingSeconds`, então só
/// ela redesenha a cada segundo — e não a tela inteira.
private struct TimerView: View {
    let timer: FocusTimer

    var body: some View {
        HStack(spacing: ClaraSpacing.small) {
            Text("♡").foregroundStyle(ClaraColor.brandDot).accessibilityHidden(true)
            Text(timer.clockLabel)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(ClaraColor.lavenderDeep)
                .contentTransition(.numericText(countsDown: true))
        }
        .frame(maxWidth: .infinity, minHeight: 46)
        .background(ClaraColor.paper, in: RoundedRectangle(cornerRadius: ClaraRadius.control))
        .overlay(RoundedRectangle(cornerRadius: ClaraRadius.control).strokeBorder(ClaraColor.line))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tempo restante")
        .accessibilityValue(timer.spokenLabel)
        .accessibilityIdentifier("today.timer")
    }
}

// MARK: - Outras tarefas

private struct OtherTasksSection: View {
    let viewModel: TodayViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: ClaraSpacing.medium) {
            SectionHeader(eyebrow: "Outras coisas", title: "Quando fizer sentido") {
                Button(action: viewModel.addTaskTapped) {
                    Image(systemName: "plus")
                        .font(.headline)
                        .foregroundStyle(ClaraColor.lavenderDeep)
                        .frame(width: 44, height: 44)
                        .background(ClaraColor.lavender, in: RoundedRectangle(cornerRadius: 11))
                }
                .accessibilityLabel("Adicionar uma tarefa")
                .accessibilityIdentifier("today.addTask")
            }
            if viewModel.otherTasks.isEmpty {
                Text("Seu foco pode ser só esse por enquanto.")
                    .font(.footnote)
                    .foregroundStyle(ClaraColor.muted)
            } else {
                ForEach(viewModel.otherTasks) { task in
                    Button {
                        Task { await viewModel.chooseFocus(task) }
                    } label: {
                        HStack(spacing: ClaraSpacing.medium) {
                            Circle().strokeBorder(ClaraColor.lavenderDeep.opacity(0.5), lineWidth: 1.5)
                                .frame(width: 15, height: 15)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title).font(.subheadline.weight(.semibold)).foregroundStyle(ClaraColor.ink)
                                if !task.nextAction.isEmpty {
                                    Text(task.nextAction).font(.caption).foregroundStyle(ClaraColor.muted)
                                }
                            }
                            Spacer()
                            Text("↗").foregroundStyle(ClaraColor.lavenderDeep).accessibilityHidden(true)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Escolher como foco")
                }
            }
        }
        .claraCard()
    }
}

// MARK: - Guardar para depois

private struct ParkingSection: View {
    @Bindable var viewModel: TodayViewModel
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ClaraSpacing.medium) {
            SectionHeader(eyebrow: "Um lugar para guardar", title: "Isso pode esperar")
            Text("Anote a ideia e volte ao que estava fazendo.")
                .font(.footnote)
                .foregroundStyle(ClaraColor.muted)
            HStack(spacing: ClaraSpacing.small) {
                TextField("Uma ideia que chegou agora…", text: $viewModel.parkingText)
                    .focused($isFieldFocused)
                    .submitLabel(.done)
                    .onSubmit(save)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(ClaraColor.paper, in: RoundedRectangle(cornerRadius: 11))
                    .accessibilityLabel("Anotar algo para depois")
                    .accessibilityIdentifier("parking.field")
                Button(action: save) {
                    Image(systemName: "plus")
                        .frame(width: 44, height: 44)
                        .foregroundStyle(ClaraColor.sageInk)
                        .background(ClaraColor.paper, in: RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityLabel("Guardar para depois")
                .accessibilityIdentifier("parking.add")
            }
            ForEach(viewModel.parkingNotes) { note in
                Button {
                    Task { await viewModel.completeParkingNote(note) }
                } label: {
                    HStack(spacing: 9) {
                        RoundedRectangle(cornerRadius: 5).strokeBorder(ClaraColor.sageInk, lineWidth: 1.5)
                            .frame(width: 15, height: 15)
                        Text(note.text).font(.footnote).foregroundStyle(ClaraColor.ink)
                        Spacer()
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Concluir: \(note.text)")
            }
        }
        .claraCard(background: ClaraColor.sage, border: ClaraColor.sage)
    }

    private func save() {
        isFieldFocused = false
        Task { await viewModel.addParkingNote() }
    }
}

// MARK: - Feriado

private struct HolidayBanner: View {
    let holiday: Holiday

    var body: some View {
        HStack(alignment: .top, spacing: ClaraSpacing.medium) {
            Image(systemName: "calendar").foregroundStyle(ClaraColor.lavenderDeep).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Feriado chegando: \(holiday.name)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ClaraColor.ink)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(ClaraColor.muted)
            }
        }
        .claraCard(background: ClaraColor.sunshine, border: ClaraColor.sunshine)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        guard let date = holiday.day?.startOfDay(in: .current) else { return "Planeje com calma." }
        return "\(ClaraFormat.shortDate(date)) · Planeje com calma, sem cobrança."
    }
}
