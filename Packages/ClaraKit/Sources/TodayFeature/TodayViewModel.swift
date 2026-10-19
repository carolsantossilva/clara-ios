import ClaraAI
import ClaraCore
import ClaraDesignSystem
import ClaraServices
import Foundation
import Observation
import os

/// The navigation the ViewModel can ask for. It knows no views or sheets:
/// it only states the intent ("show the pause"). The Coordinator decides *how*.
@MainActor
public protocol TodayRouting: AnyObject {
    func presentAddTask()
    func presentPause(for task: FocusTask)
    func presentStepSuggestions(for task: FocusTask)
    func presentPrivacy()
    func dismissSheet()
}

/// State and rules of the Today screen (the "VM" in MVVM-C).
///
/// - `@MainActor`: all state the UI reads lives on the main actor. Without it, updating
///   `tasks` after an `await` could happen off the main thread.
/// - `@Observable`: the view redraws when the properties it read change.
@MainActor
@Observable
public final class TodayViewModel {
    public private(set) var tasks: [FocusTask] = []
    public private(set) var parkingNotes: [ParkingNote] = []
    public private(set) var focusID: UUID?
    public private(set) var isLoading = true
    public private(set) var upcomingHoliday: Holiday?
    public var parkingText = ""
    public var alert: AlertContent?
    public let timer: FocusTimer

    // `weak`: the Coordinator owns the ViewModel; the back reference must not retain it.
    // `@ObservationIgnored`: dependencies and the router are not screen state.
    @ObservationIgnored weak var router: (any TodayRouting)?

    @ObservationIgnored private let dependencies: TodayDependencies
    @ObservationIgnored private let signposter = OSSignposter(subsystem: "app.clara", category: "Today")

    public init(dependencies: TodayDependencies) {
        self.dependencies = dependencies
        self.timer = FocusTimer(durationSeconds: 15 * 60, clock: dependencies.clock)
    }

    // MARK: Derived state

    public var focus: FocusTask? {
        tasks.first { $0.id == focusID } ?? tasks.first
    }

    public var otherTasks: [FocusTask] {
        tasks.filter { $0.id != focus?.id }
    }

    /// Duration comes from the A/B test (15 or 25 min).
    public var focusMinutes: Int {
        dependencies.flags.variant(.focusDuration).flatMap(Int.init) ?? 15
    }

    public var showsStepSuggestions: Bool {
        dependencies.flags.isEnabled(.aiStepSuggestions)
    }

    // MARK: Loading

    /// Called by the view's `.task`: cancelled automatically if the view leaves the screen.
    public func onAppear() async {
        // `async let` over MainActor methods: the two loads interleave at the
        // `await` points (concurrency), but they do not run in parallel on the CPU.
        async let content: Void = load()
        async let holiday: Void = loadHoliday()
        _ = await (content, holiday)
    }

    func load() async {
        // Interval visible in Instruments (Points of Interest / os_signpost).
        let state = signposter.beginInterval("TodayLoad")
        defer { signposter.endInterval("TodayLoad", state) }

        // Copy into local constants: `async let` runs in a child task and must not
        // touch MainActor-isolated state (`self.dependencies`) from there.
        let taskRepository = dependencies.tasks
        let parkingRepository = dependencies.parking
        do {
            // Three reads in parallel, like the original app's `Promise.all`.
            async let openTasks = taskRepository.listOpen()
            async let openNotes = parkingRepository.listOpen()
            async let currentFocus = taskRepository.focusID()
            (tasks, parkingNotes, focusID) = try await (openTasks, openNotes, currentFocus)
        } catch is CancellationError {
            return
        } catch {
            report(
                error,
                context: "today.load",
                title: "Não foi possível abrir seus registros",
                message: "Nada foi alterado. Tente fechar e abrir o app novamente."
            )
        }
        isLoading = false
    }

    func loadHoliday() async {
        guard dependencies.flags.isEnabled(.holidayBanner) else { return }
        let today = LocalDay(dependencies.now(), in: .current)
        // The holiday is a nice-to-have: if the network fails, the screen goes on without it, no alert.
        upcomingHoliday = try? await dependencies.holidays.upcomingHoliday(from: today, within: 7)
        if upcomingHoliday != nil {
            dependencies.analytics.track(.holidayBannerShown)
        }
    }

    // MARK: Tasks

    /// - Returns: `true` if it saved (the sheet can close).
    @discardableResult
    public func createTask(title: String, nextAction: String) async -> Bool {
        guard !title.trimmed.isEmpty else { return false }
        do {
            _ = try await dependencies.tasks.create(title: title, nextAction: nextAction)
            dependencies.analytics.track(.taskCreated(hasFirstStep: !nextAction.trimmed.isEmpty))
            router?.dismissSheet()
            await load()
            return true
        } catch {
            report(error, context: "today.createTask", title: "Não foi possível salvar", message: "A tarefa continua aqui. Tente novamente.")
            return false
        }
    }

    public func chooseFocus(_ task: FocusTask) async {
        do {
            try await dependencies.tasks.setFocus(task.id)
            focusID = task.id
            timer.stop()
        } catch {
            report(error, context: "today.chooseFocus", title: "Não foi possível trocar o foco", message: "Sua tarefa continua salva no aparelho.")
        }
    }

    public func startFocus() async {
        guard let focus else { return }
        await chooseFocus(focus)
        guard focusID == focus.id else { return }
        timer.start(durationSeconds: focusMinutes * 60)
        dependencies.analytics.track(.focusStarted(minutes: focusMinutes, variant: dependencies.flags.variant(.focusDuration)))
    }

    public func pause(whereStopped: String, nextStep: String) async {
        guard let focus else { return }
        do {
            let resumeStep = nextStep.trimmed.isEmpty ? focus.nextAction : nextStep
            try await dependencies.tasks.savePause(id: focus.id, whereStopped: whereStopped, nextAction: resumeStep)
            timer.stop()
            dependencies.analytics.track(.focusPaused(savedClue: !whereStopped.trimmed.isEmpty))
            router?.dismissSheet()
            await load()
        } catch {
            report(error, context: "today.pause", title: "Não foi possível salvar a pausa", message: "Sua tarefa continua salva no aparelho.")
        }
    }

    public func completeFocus() async {
        guard let focus else { return }
        do {
            try await dependencies.tasks.setState(id: focus.id, .done)
            timer.stop()
            dependencies.analytics.track(.taskCompleted)
            await load()
        } catch {
            report(error, context: "today.complete", title: "Não foi possível concluir a tarefa", message: "Tente novamente em instantes.")
        }
    }

    public func acceptSuggestedStep(_ step: String, for task: FocusTask, source: StepSuggestion.Source) async {
        do {
            try await dependencies.tasks.updateNextAction(id: task.id, nextAction: step)
            dependencies.analytics.track(.stepSuggestionAccepted(source: source.rawValue))
            router?.dismissSheet()
            await load()
        } catch {
            report(error, context: "today.acceptStep", title: "Não foi possível salvar o passo", message: "Tente novamente em instantes.")
        }
    }

    // MARK: Park for later

    public func addParkingNote() async {
        let text = parkingText.trimmed
        guard !text.isEmpty else { return }
        do {
            try await dependencies.parking.create(text: text)
            parkingText = ""
            dependencies.analytics.track(.parkingNoteSaved)
            await load()
        } catch {
            report(error, context: "today.addParking", title: "Não foi possível guardar", message: "Tente novamente em instantes.")
        }
    }

    public func completeParkingNote(_ note: ParkingNote) async {
        do {
            try await dependencies.parking.complete(id: note.id)
            await load()
        } catch {
            report(error, context: "today.completeParking", title: "Não foi possível atualizar a anotação", message: "Tente novamente em instantes.")
        }
    }

    // MARK: Navigation

    public func addTaskTapped() { router?.presentAddTask() }
    public func privacyTapped() { router?.presentPrivacy() }

    public func pauseTapped() {
        guard let focus else { return }
        router?.presentPause(for: focus)
    }

    public func suggestStepsTapped() {
        guard let focus else { return }
        router?.presentStepSuggestions(for: focus)
    }

    // MARK: Errors

    private func report(_ error: any Error, context: String, title: String, message: String) {
        dependencies.crashReporter.record(error, context: context)
        alert = AlertContent(title: title, message: message)
    }
}

/// ViewModel for the suggestions sheet. Lives while the sheet is open.
@MainActor
@Observable
public final class StepSuggestionsViewModel: Identifiable {
    public enum State: Equatable {
        case loading
        case loaded(StepSuggestion)
        case failed
    }

    public let task: FocusTask
    public private(set) var state: State = .loading
    public nonisolated var id: UUID { task.id }

    @ObservationIgnored private let suggester: any StepSuggesting
    @ObservationIgnored private let analytics: any AnalyticsTracker

    public init(task: FocusTask, suggester: any StepSuggesting, analytics: any AnalyticsTracker) {
        self.task = task
        self.suggester = suggester
        self.analytics = analytics
    }

    public func load() async {
        state = .loading
        do {
            let suggestion = try await suggester.suggestSteps(for: task.title)
            state = .loaded(suggestion)
            analytics.track(.stepSuggestionsShown(source: suggestion.source.rawValue))
        } catch is CancellationError {
            return
        } catch {
            state = .failed
        }
    }
}
