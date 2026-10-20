import ClaraInfrastructure
import ClaraCore
import ClaraTestSupport
import Foundation
import Testing
@testable import ClaraUI

/// ViewModel tests use the real database in memory.
/// Using the real (in-memory) repository instead of a mock makes the test less brittle:
/// it checks behavior, not the exact sequence of internal calls.
@Suite("Today screen")
@MainActor
struct TodayViewModelTests {
    let database = LocalDatabase(inMemory: .init())
    let analytics = SpyAnalyticsTracker()
    let crashReporter = SpyCrashReporter()
    let now = SteppingNow()

    func makeViewModel(
        tasks: (any TaskRepository)? = nil,
        holidays: any HolidayProviding = StaticHolidayProvider()
    ) -> TodayViewModel {
        let viewModel = TodayViewModel(dependencies: TodayDependencies(
            tasks: tasks ?? LocalTaskRepository(database: database, now: now.read),
            parking: LocalParkingRepository(database: database, now: now.read),
            suggester: StubStepSuggester(.succeed(["Abrir a conversa"])),
            holidays: holidays,
            analytics: analytics,
            crashReporter: crashReporter,
            clock: ImmediateClock(),
            now: { Fixtures.date("2026-10-10T12:00:00-03:00") }
        ))
        return viewModel
    }

    @Test("with no focus chosen, the newest task becomes the focus")
    func defaultsFocusToMostRecent() async {
        let viewModel = makeViewModel()
        await viewModel.createTask(title: "Antiga", nextAction: "")
        await viewModel.createTask(title: "Recente", nextAction: "")

        #expect(viewModel.focus?.title == "Recente")
        #expect(viewModel.otherTasks.map(\.title) == ["Antiga"])
    }

    @Test("creating a task succeeds and logs the event without the task text")
    func createTaskTracksMetadata() async {
        let viewModel = makeViewModel()

        let saved = await viewModel.createTask(title: "Responder a clínica", nextAction: "abrir a conversa")

        #expect(saved)
        #expect(analytics.events == [AnalyticsEvent(name: "task_created", properties: ["has_first_step": "true"])])
    }

    @Test("an empty title creates no task")
    func ignoresEmptyTitle() async {
        let viewModel = makeViewModel()
        let saved = await viewModel.createTask(title: "   ", nextAction: "")
        #expect(!saved)
        #expect(viewModel.tasks.isEmpty)
    }

    @Test("the focus duration follows the user selection")
    func focusDurationFromSelection() async {
        let viewModel = makeViewModel()
        viewModel.focusMinutes = 25
        await viewModel.createTask(title: "Escrever", nextAction: "")

        await viewModel.startFocus()

        #expect(viewModel.focusMinutes == 25)
        #expect(analytics.events.last == AnalyticsEvent(name: "focus_started", properties: ["minutes": "25"]))
        viewModel.timer.stop()
    }

    @Test("pausing without a new step keeps the previous step")
    func pauseKeepsPreviousStep() async {
        let viewModel = makeViewModel()
        await viewModel.createTask(title: "Exames", nextAction: "abrir a pasta")

        await viewModel.pause(whereStopped: "parei nos documentos", nextStep: "")

        #expect(viewModel.focus?.whereStopped == "parei nos documentos")
        #expect(viewModel.focus?.nextAction == "abrir a pasta")
    }

    @Test("accepting a suggested step makes it the task's next step")
    func acceptSuggestedStep() async throws {
        let viewModel = makeViewModel()
        await viewModel.createTask(title: "Exames", nextAction: "")
        let task = try #require(viewModel.focus)

        await viewModel.acceptSuggestedStep("Abrir a pasta", for: task, source: .onDevice)

        #expect(viewModel.focus?.nextAction == "Abrir a pasta")
        #expect(analytics.names.contains("step_suggestion_accepted"))
    }

    @Test("a load failure shows an alert and reports to the crash reporter")
    func loadFailureShowsAlert() async {
        let viewModel = makeViewModel(tasks: FailingTaskRepository())

        await viewModel.load()

        #expect(viewModel.alert?.title == "Não foi possível abrir seus registros")
        #expect(crashReporter.contexts == ["today.load"])
        #expect(!viewModel.isLoading)
    }

    @Test("the upcoming holiday is loaded when available")
    func loadsHoliday() async {
        let holiday = Holiday(date: "2026-10-12", name: "Nossa Senhora Aparecida")
        let viewModel = makeViewModel(holidays: StaticHolidayProvider(holiday: holiday))
        await viewModel.loadHoliday()
        #expect(viewModel.upcomingHoliday == holiday)
    }

    @Test("parking for later clears the field and lists the note")
    func parkingNote() async {
        let viewModel = makeViewModel()
        viewModel.parkingText = "  comprar pilhas  "

        await viewModel.addParkingNote()

        #expect(viewModel.parkingText.isEmpty)
        #expect(viewModel.parkingNotes.map(\.text) == ["comprar pilhas"])
    }
    @Test("a failed creation reports failure so the form stays open")
    func failedCreationKeepsDraft() async {
        let viewModel = makeViewModel(tasks: FailingTaskRepository())
        #expect(await viewModel.createTask(title: "Exames", nextAction: "") == false)
        #expect(viewModel.alert?.title == "Não foi possível salvar")
        #expect(analytics.events.isEmpty)
    }

    @Test("pausing without a task cannot report success")
    func cannotPauseWithoutFocus() async {
        let viewModel = makeViewModel()
        #expect(await viewModel.pause(whereStopped: "pista", nextStep: "passo") == false)
        #expect(analytics.events.isEmpty)
    }

    @Test("completion advances focus to the next open task")
    func completesAndAdvancesFocus() async {
        let viewModel = makeViewModel()
        await viewModel.createTask(title: "Depois", nextAction: "")
        await viewModel.createTask(title: "Agora", nextAction: "")
        await viewModel.completeFocus()
        #expect(viewModel.tasks.map(\.title) == ["Depois"])
        #expect(viewModel.focus?.title == "Depois")
        #expect(analytics.names.last == "task_completed")
    }

    @Test("choosing another task stops the current focus session")
    func changingFocusStopsTimer() async throws {
        let viewModel = makeViewModel()
        await viewModel.createTask(title: "Primeira", nextAction: "")
        let first = try #require(viewModel.focus)
        await viewModel.createTask(title: "Segunda", nextAction: "")
        await viewModel.startFocus()
        await viewModel.chooseFocus(first)
        #expect(viewModel.focus?.id == first.id)
        #expect(!viewModel.timer.isRunning)
    }

    @Test("completing a parked idea removes it from the open list")
    func completesParkingNote() async throws {
        let viewModel = makeViewModel()
        viewModel.parkingText = "Comprar pilhas"
        await viewModel.addParkingNote()
        await viewModel.completeParkingNote(try #require(viewModel.parkingNotes.first))
        #expect(viewModel.parkingNotes.isEmpty)
    }

    @Test("blank parked ideas are not stored or tracked")
    func ignoresEmptyParkingNote() async {
        let viewModel = makeViewModel()
        viewModel.parkingText = "   "
        await viewModel.addParkingNote()
        #expect(viewModel.parkingNotes.isEmpty)
        #expect(analytics.events.isEmpty)
    }

    @Test("failed suggested-step saves leave the suggestion available to retry")
    func reportsSuggestedStepFailure() async {
        let viewModel = makeViewModel(tasks: FailingTaskRepository())
        let task = FocusTask(title: "Exames", updatedAt: Fixtures.date("2026-10-10T12:00:00-03:00"))
        #expect(await viewModel.acceptSuggestedStep("Abrir pasta", for: task, source: .heuristic) == false)
        #expect(viewModel.alert?.title == "Não foi possível salvar o passo")
        #expect(analytics.events.isEmpty)
    }

    @Test("the suggestions sheet uses the feature's injected provider")
    func loadsInjectedSuggestions() async throws {
        let viewModel = makeViewModel()
        await viewModel.createTask(title: "Exames", nextAction: "")
        let suggestions = viewModel.makeStepSuggestions(for: try #require(viewModel.focus))
        await suggestions.load()
        #expect(suggestions.state == .loaded(.init(steps: ["Abrir a conversa"], source: .onDevice)))
        #expect(analytics.names.last == "step_suggestions_shown")
    }

    @Test("a suggestion failure produces a retryable error state")
    func reportsSuggestionFailure() async {
        let task = FocusTask(title: "Exames", updatedAt: Fixtures.date("2026-10-10T12:00:00-03:00"))
        let suggestions = StepSuggestionsViewModel(task: task, suggester: StubStepSuggester(.fail), analytics: analytics)
        await suggestions.load()
        #expect(suggestions.state == .failed)
        #expect(analytics.events.isEmpty)
    }

    @Test("stopping a timer cancels its loop without marking it finished")
    func stopsTimer() async {
        let timer = FocusTimer(durationSeconds: 60, clock: ImmediateClock())
        timer.start(durationSeconds: 60)
        timer.stop()
        await timer.waitUntilFinished()
        #expect(!timer.isRunning)
        #expect(!timer.didFinish)
        #expect(timer.remainingSeconds == 60)
    }

}

@Suite("Focus timer")
@MainActor
struct FocusTimerTests {
    @Test("counts down to zero and marks as finished")
    func countsDown() async {
        let timer = FocusTimer(durationSeconds: 0, clock: ImmediateClock())

        timer.start(durationSeconds: 3)
        await timer.waitUntilFinished()

        #expect(timer.remainingSeconds == 0)
        #expect(timer.didFinish)
        #expect(!timer.isRunning)
    }

    @Test("formats visual and spoken countdown labels")
    func labels() {
        let timer = FocusTimer(durationSeconds: 14 * 60 + 5, clock: ImmediateClock())
        #expect(timer.clockLabel == "14:05")
        #expect(timer.spokenLabel == "14 minutos e 5 segundos")
    }
}
