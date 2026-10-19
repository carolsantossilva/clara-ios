import ClaraAI
import ClaraCore
import ClaraServices
import ClaraStorage
import ClaraTestSupport
import Foundation
import Testing
@testable import TodayFeature

/// Testes do ViewModel sem SwiftUI: o router é um espião e o banco é real, em memória.
/// Usar o repositório real (em memória) em vez de um mock deixa o teste menos frágil:
/// ele verifica comportamento, não a sequência exata de chamadas internas.
@Suite("Tela Hoje")
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

    @Test("sem foco escolhido, a tarefa mais recente vira o foco")
    func defaultsFocusToMostRecent() async {
        let viewModel = makeViewModel()
        await viewModel.createTask(title: "Antiga", nextAction: "")
        await viewModel.createTask(title: "Recente", nextAction: "")

        #expect(viewModel.focus?.title == "Recente")
        #expect(viewModel.otherTasks.map(\.title) == ["Antiga"])
    }

    @Test("criar tarefa fecha a sheet e registra o evento sem o texto da tarefa")
    func createTaskDismissesAndTracks() async {
        let viewModel = makeViewModel()

        let saved = await viewModel.createTask(title: "Responder a clínica", nextAction: "abrir a conversa")

        #expect(saved)
        #expect(router.dismissCount == 1)
        #expect(analytics.events == [AnalyticsEvent(name: "task_created", properties: ["has_first_step": "true"])])
    }

    @Test("título vazio não cria tarefa")
    func ignoresEmptyTitle() async {
        let viewModel = makeViewModel()
        let saved = await viewModel.createTask(title: "   ", nextAction: "")
        #expect(!saved)
        #expect(viewModel.tasks.isEmpty)
    }

    @Test("a duração do foco vem da variante do teste A/B")
    func focusDurationFromExperiment() async {
        let flags = FeatureFlags(config: RemoteConfig(flags: [:], experiments: ["focus_duration": ["25"]]))
        let viewModel = makeViewModel(flags: flags)
        await viewModel.createTask(title: "Escrever", nextAction: "")

        await viewModel.startFocus()

        #expect(viewModel.focusMinutes == 25)
        #expect(analytics.events.last == AnalyticsEvent(name: "focus_started", properties: ["minutes": "25", "variant": "25"]))
        viewModel.timer.stop()
    }

    @Test("pausar sem novo passo mantém o passo anterior")
    func pauseKeepsPreviousStep() async {
        let viewModel = makeViewModel()
        await viewModel.createTask(title: "Exames", nextAction: "abrir a pasta")

        await viewModel.pause(whereStopped: "parei nos documentos", nextStep: "")

        #expect(viewModel.focus?.whereStopped == "parei nos documentos")
        #expect(viewModel.focus?.nextAction == "abrir a pasta")
    }

    @Test("aceitar um passo sugerido vira o próximo passo da tarefa")
    func acceptSuggestedStep() async throws {
        let viewModel = makeViewModel()
        await viewModel.createTask(title: "Exames", nextAction: "")
        let task = try #require(viewModel.focus)

        await viewModel.acceptSuggestedStep("Abrir a pasta", for: task, source: .onDevice)

        #expect(viewModel.focus?.nextAction == "Abrir a pasta")
        #expect(analytics.names.contains("step_suggestion_accepted"))
    }

    @Test("falha ao carregar mostra alerta e registra no crash reporter")
    func loadFailureShowsAlert() async {
        let viewModel = makeViewModel(tasks: FailingTaskRepository())

        await viewModel.load()

        #expect(viewModel.alert?.title == "Não foi possível abrir seus registros")
        #expect(crashReporter.contexts == ["today.load"])
        #expect(!viewModel.isLoading)
    }

    @Test("feriado só aparece com a flag ligada")
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

    @Test("guardar para depois limpa o campo e lista a anotação")
    func parkingNote() async {
        let viewModel = makeViewModel()
        viewModel.parkingText = "  comprar pilhas  "

        await viewModel.addParkingNote()

        #expect(viewModel.parkingText.isEmpty)
        #expect(viewModel.parkingNotes.map(\.text) == ["comprar pilhas"])
    }
}

@Suite("Timer de foco")
@MainActor
struct FocusTimerTests {
    @Test("conta até zero e marca como terminado")
    func countsDown() async {
        let timer = FocusTimer(durationSeconds: 0, clock: ImmediateClock())

        timer.start(durationSeconds: 3)
        await timer.waitUntilFinished()

        #expect(timer.remainingSeconds == 0)
        #expect(timer.didFinish)
        #expect(!timer.isRunning)
    }

    @Test("rótulos vêm do formatador Objective-C")
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
