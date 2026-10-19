import ClaraCore
import ClaraServices
import ClaraStorage
import ClaraTestSupport
import Foundation
import SwiftUI
import Testing
@testable import TodayFeature

/// The real coordinator wired to the real view model: checks that taps on the screen
/// open the right sheet, with no SwiftUI on screen.
@Suite("Today screen — Coordinator")
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

    @Test("the view model navigates through the coordinator")
    func viewModelRoutesThroughCoordinator() {
        let coordinator = makeCoordinator()

        coordinator.viewModel.addTaskTapped()
        #expect(coordinator.sheet?.id == "addTask")

        coordinator.viewModel.privacyTapped()
        #expect(coordinator.sheet?.id == "privacy")
    }

    @Test("creating a task closes the sheet; pausing opens the pause for the focused task")
    func createThenPause() async throws {
        let coordinator = makeCoordinator()
        coordinator.viewModel.addTaskTapped()

        await coordinator.viewModel.createTask(title: "Responder e-mail", nextAction: "")
        #expect(coordinator.sheet == nil)

        let focus = try #require(coordinator.viewModel.focus)
        coordinator.viewModel.pauseTapped()
        #expect(coordinator.sheet?.id == "pause-\(focus.id)")
    }

    @Test("suggesting steps opens the sheet with the injected suggester")
    func stepSuggestionsUseInjectedSuggester() async throws {
        let coordinator = makeCoordinator()
        await coordinator.viewModel.createTask(title: "Responder e-mail", nextAction: "")
        let focus = try #require(coordinator.viewModel.focus)

        coordinator.viewModel.suggestStepsTapped()

        guard case .steps(let steps)? = coordinator.sheet else {
            Issue.record("expected the steps sheet, got \(String(describing: coordinator.sheet?.id))")
            return
        }
        #expect(steps.task.id == focus.id)
        await steps.load()
        guard case .loaded(let suggestion) = steps.state else {
            Issue.record("expected loaded suggestions, got \(steps.state)")
            return
        }
        #expect(suggestion.steps == ["Abrir a conversa"])
    }

    @Test("with no focused task, pause and suggest open nothing")
    func nothingToPauseWithoutFocus() {
        let coordinator = makeCoordinator()

        coordinator.viewModel.pauseTapped()
        coordinator.viewModel.suggestStepsTapped()

        #expect(coordinator.sheet == nil)
    }
}
