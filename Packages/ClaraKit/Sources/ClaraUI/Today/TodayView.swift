import ClaraCore
import ClaraInfrastructure
import SwiftUI

/// The Today screen. SwiftUI views are cheap *descriptions* of the interface: `body`
/// can be recomputed many times, so we keep no state in them; it lives in the
/// ViewModel (`@Observable`) or in `@State` for view-local things.
public struct TodayView<PrivacyContent: View>: View {
    // `@Bindable` allows creating bindings (`$viewModel.parkingText`) to an @Observable object.
    @Bindable var viewModel: TodayViewModel
    @AppStorage("focus.minutes") private var preferredFocusMinutes = 15
    @State private var sheet: Sheet?
    private let privacyContent: () -> PrivacyContent

    private enum Sheet: Identifiable {
        case addTask
        case pause(FocusTask)
        case steps(StepSuggestionsViewModel)
        case privacy

        var id: String {
            switch self {
            case .addTask: "addTask"
            case .pause(let task): "pause-\(task.id)"
            case .steps(let viewModel): "steps-\(viewModel.id)"
            case .privacy: "privacy"
            }
        }
    }

    public init(viewModel: TodayViewModel, @ViewBuilder privacyContent: @escaping () -> PrivacyContent) {
        self.viewModel = viewModel
        self.privacyContent = privacyContent
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ClaraSpacing.large) {
                BrandHeader {
                    Button { sheet = .privacy } label: { LocalOnlyBadge() }
                        .accessibilityHint("Abre informações de privacidade")
                        .accessibilityIdentifier("today.privacyBadge")
                }
                PageHeading(
                    eyebrow: "Seu cantinho de hoje",
                    title: "Um passo de cada vez",
                    subtitle: "O que cabe agora já é suficiente."
                )
                if let holiday = viewModel.upcomingHoliday {
                    HolidayBanner(holiday: holiday)
                }
                FocusSection(
                    viewModel: viewModel,
                    onAdd: { sheet = .addTask },
                    onPause: { if let task = viewModel.focus { sheet = .pause(task) } },
                    onSuggest: {
                        if let task = viewModel.focus { sheet = .steps(viewModel.makeStepSuggestions(for: task)) }
                    }
                )
                if !viewModel.tasks.isEmpty {
                    OtherTasksSection(viewModel: viewModel, onAdd: { sheet = .addTask })
                }
                ParkingSection(viewModel: viewModel)
                Text("Você pode começar pelo que está mais perto.")
                    .font(.footnote)
                    .foregroundStyle(ClaraColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, ClaraSpacing.large)
            .padding(.bottom, ClaraSpacing.extraLarge)
        }
        .background(ClaraColor.background.ignoresSafeArea())
        // `.task` starts when the view appears and is cancelled when it goes away.
        .task {
            viewModel.focusMinutes = preferredFocusMinutes == 25 ? 25 : 15
            await viewModel.onAppear()
        }
        .onChange(of: viewModel.focusMinutes) { _, minutes in preferredFocusMinutes = minutes }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .addTask: AddTaskSheet(viewModel: viewModel)
            case .pause(let task): PauseSheet(task: task, viewModel: viewModel)
            case .steps(let suggestions):
                StepSuggestionsSheet(viewModel: suggestions) { step, source in
                    await viewModel.acceptSuggestedStep(step, for: suggestions.task, source: source)
                }
            case .privacy: privacyContent()
            }
        }
        .claraAlert($viewModel.alert)
    }
}

// MARK: - Focus

private struct FocusSection: View {
    let viewModel: TodayViewModel
    let onAdd: () -> Void
    let onPause: () -> Void
    let onSuggest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ClaraSpacing.medium) {
            if viewModel.isLoading {
                ProgressView("Abrindo seu espaço…")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if let focus = viewModel.focus {
                TaskCard(task: focus)
                FocusActions(viewModel: viewModel, onPause: onPause, onSuggest: onSuggest)
            } else {
                EmptyStateView()
                Button("Adicionar uma tarefa ＋", action: onAdd)
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
                    .font(.caption2.weight(.bold))
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
    @Bindable var viewModel: TodayViewModel
    let onPause: () -> Void
    let onSuggest: () -> Void

    var body: some View {
        VStack(spacing: ClaraSpacing.small) {
            Picker("Tempo de foco", selection: $viewModel.focusMinutes) {
                Text("15 min").tag(15)
                Text("25 min").tag(25)
            }
            .pickerStyle(.segmented)
            .disabled(viewModel.timer.isRunning)
            .accessibilityIdentifier("today.focusDuration")
            if viewModel.timer.isRunning {
                TimerView(timer: viewModel.timer)
            } else {
                Button("Começar por \(viewModel.focusMinutes) min →") {
                    Task { await viewModel.startFocus() }
                }
                .buttonStyle(.claraPrimary)
                .accessibilityIdentifier("today.startFocus")
            }
            Button("Pausar e salvar", action: onPause)
                .buttonStyle(.claraSecondary)
                .accessibilityIdentifier("today.pause")
            Button("✨ Sugerir passos pequenos", action: onSuggest)
                .buttonStyle(.claraSecondary)
                .accessibilityIdentifier("today.suggestSteps")
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

/// A small view, separate on purpose: only it reads `remainingSeconds`, so only
/// it redraws every second, not the whole screen.
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

// MARK: - Other tasks

private struct OtherTasksSection: View {
    let viewModel: TodayViewModel
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ClaraSpacing.medium) {
            SectionHeader(eyebrow: "Outras coisas", title: "Quando fizer sentido") {
                Button(action: onAdd) {
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

// MARK: - Park for later

private struct ParkingSection: View {
    @Bindable var viewModel: TodayViewModel
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ClaraSpacing.medium) {
            SectionHeader(eyebrow: "Um lugar para guardar", title: "Isso pode esperar")
            Text("Anote a ideia e volte ao que estava fazendo.")
                .font(.footnote)
                .foregroundStyle(ClaraColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: ClaraSpacing.small) {
                TextField("Uma ideia para depois…", text: $viewModel.parkingText, axis: .vertical)
                    .lineLimit(1...3)
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

// MARK: - Holiday

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
