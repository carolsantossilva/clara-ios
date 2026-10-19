import ClaraCore
import ClaraServices
import ClaraStorage
import ClaraTestSupport
import Foundation
import SwiftUI
import Testing
@testable import TodayFeature

/// O coordinator real ligado ao ViewModel real: confere que os toques da tela
/// abrem a sheet certa, sem SwiftUI na tela.
@Suite("Tela Hoje — Coordinator")
@MainActor
struct TodayCoordinatorTests {
    let database = LocalDatabase(inMemory: .init())
    let now = SteppingNow()

    func makeCoordinator() -> TodayCoordinator {
        TodayCoordinator(
            dependencies: TodayDependencies(
                tasks: LocalTaskRepository(database: database, now: now.read),
                parking: LocalParkingRepository(database: database, now: now.read),
                suggester: StubStepSuggester(.succeed(["Abrir a conversa"])),
                holidays: StaticHolidayProvider(),
                flags: FeatureFlags(),
                analytics: SpyAnalyticsTracker(),
                crashReporter: SpyCrashReporter(),
                clock: ImmediateClock(),
                now: { Fixtures.date("2026-10-10T12:00:00-03:00") }
            ),
            makePrivacyView: { AnyView(EmptyView()) }
        )
    }

    @Test("o ViewModel navega pelo coordinator")
    func viewModelRoutesThroughCoordinator() {
        let coordinator = makeCoordinator()

        coordinator.viewModel.addTaskTapped()
        #expect(coordinator.sheet?.id == "addTask")

        coordinator.viewModel.privacyTapped()
        #expect(coordinator.sheet?.id == "privacy")
    }

    @Test("criar tarefa fecha a sheet; pausar abre a pausa da tarefa em foco")
    func createThenPause() async throws {
        let coordinator = makeCoordinator()
        coordinator.viewModel.addTaskTapped()

        await coordinator.viewModel.createTask(title: "Responder e-mail", nextAction: "")
        #expect(coordinator.sheet == nil)

        let focus = try #require(coordinator.viewModel.focus)
        coordinator.viewModel.pauseTapped()
        #expect(coordinator.sheet?.id == "pause-\(focus.id)")
    }

    @Test("sugerir passos abre a sheet com o sugeridor das dependências")
    func stepSuggestionsUseInjectedSuggester() async throws {
        let coordinator = makeCoordinator()
        await coordinator.viewModel.createTask(title: "Responder e-mail", nextAction: "")
        let focus = try #require(coordinator.viewModel.focus)

        coordinator.viewModel.suggestStepsTapped()

        guard case .steps(let steps)? = coordinator.sheet else {
            Issue.record("esperava a sheet de passos, veio \(String(describing: coordinator.sheet?.id))")
            return
        }
        #expect(steps.task.id == focus.id)
        await steps.load()
        guard case .loaded(let suggestion) = steps.state else {
            Issue.record("esperava sugestões carregadas, veio \(steps.state)")
            return
        }
        #expect(suggestion.steps == ["Abrir a conversa"])
    }

    @Test("sem tarefa em foco, pausar e sugerir não abrem nada")
    func nothingToPauseWithoutFocus() {
        let coordinator = makeCoordinator()

        coordinator.viewModel.pauseTapped()
        coordinator.viewModel.suggestStepsTapped()

        #expect(coordinator.sheet == nil)
    }
}
