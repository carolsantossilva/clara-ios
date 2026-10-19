import ClaraAI
import ClaraCore
import ClaraServices
import ClaraStorage
import ClaraTestSupport
import Foundation
import Testing
@testable import TodayFeature

/// ViewModel tests without SwiftUI: the router is a spy and the database is real, in memory.
/// Using the real (in-memory) repository instead of a mock makes the test less brittle:
/// it checks behavior, not the exact sequence of internal calls.
@Suite("Today screen")
@MainActor
struct TodayViewModelTests {
    let database = LocalDatabase(inMemory: .init())
    let analytics = SpyAnalyticsTracker()
    let crashReporter = SpyCrashReporter()
    let router = SpyTodayRouter()
    let now = SteppingNow()

    func makeViewModel(
        tasks: (any TaskRepository)? = nil,
        flags: FeatureFlags? = nil,
        holidays: any HolidayProviding = StaticHolidayProvider()
    ) -> TodayViewModel {
        let viewModel = TodayViewModel(dependencies: TodayDependencies(
            tasks: tasks ?? LocalTaskRepository(database: database, now: now.read),
            parking: LocalParkingRepository(database: database, now: now.read),
            suggester: StubStepSuggester(.succeed(["Abrir a conversa"])),
            holidays: holidays,
            flags: flags ?? FeatureFlags(),
            analytics: analytics,
            crashReporter: crashReporter,
            clock: ImmediateClock(),
            now: { Fixtures.date("2026-10-10T12:00:00-03:00") }
        ))
        viewModel.router = router
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

    @Test("creating a task closes the sheet and logs the event without the task text")
    func createTaskDismissesAndTracks() async {
        let viewModel = makeViewModel()

        let saved = await viewModel.createTask(title: "Responder a clínica", nextAction: "abrir a conversa")

        #expect(saved)
        #expect(router.dismissCount == 1)
        #expect(analytics.events == [AnalyticsEvent(name: "task_created", properties: ["has_first_step": "true"])])
    }

    @Test("an empty title creates no task")
    func ignoresEmptyTitle() async {
        let viewModel = makeViewModel()
        let saved = await viewModel.createTask(title: "   ", nextAction: "")
        #expect(!saved)
        #expect(viewModel.tasks.isEmpty)
    }

    @Test("the focus duration comes from the A/B variant")
    func focusDurationFromExperiment() async {
        let flags = FeatureFlags(config: RemoteConfig(flags: [:], experiments: ["focus_duration": ["25"]]))
        let viewModel = makeViewModel(flags: flags)
        await viewModel.createTask(title: "Escrever", nextAction: "")

        await viewModel.startFocus()

        #expect(viewModel.focusMinutes == 25)
        #expect(analytics.events.last == AnalyticsEvent(name: "focus_started", properties: ["minutes": "25", "variant": "25"]))
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

    @Test("the holiday only shows with the flag on")
    func holidayBehindFlag() async {
        let holiday = Holiday(date: "2026-10-12", name: "Nossa Senhora Aparecida")
        let flags = FeatureFlags(config: RemoteConfig(flags: ["holiday_banner": false], experiments: [:]))
        let viewModel = makeViewModel(flags: flags, holidays: StaticHolidayProvider(holiday: holiday))

        await viewModel.loadHoliday()
        #expect(viewModel.upcomingHoliday == nil)

        flags.overrides[.holidayBanner] = true
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

    @Test("labels come from the Objective-C formatter")
    func labels() {
        let timer = FocusTimer(durationSeconds: 14 * 60 + 5, clock: ImmediateClock())
        #expect(timer.clockLabel == "14:05")
        #expect(timer.spokenLabel == "14 minutos e 5 segundos")
    }
}

@MainActor
final class SpyTodayRouter: TodayRouting {
    private(set) var dismissCount = 0
    private(set) var presented: [String] = []

    func presentAddTask() { presented.append("addTask") }
    func presentPause(for task: FocusTask) { presented.append("pause") }
    func presentStepSuggestions(for task: FocusTask) { presented.append("steps") }
    func presentPrivacy() { presented.append("privacy") }
    func dismissSheet() { dismissCount += 1 }
}
