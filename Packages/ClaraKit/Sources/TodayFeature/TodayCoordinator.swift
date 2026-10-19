import ClaraCore
import ClaraDesignSystem
import Observation
import SwiftUI

/// The "C" in MVVM-C: decides *how* to navigate. The ViewModel only says *what* it wants.
///
/// Benefits: the ViewModel is testable without SwiftUI (tests use a spy router)
/// and the feature's screen flow lives in one place.
@MainActor
@Observable
public final class TodayCoordinator: TodayRouting {
    enum Sheet: Identifiable {
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

    var sheet: Sheet?
    public let viewModel: TodayViewModel

    @ObservationIgnored private let dependencies: TodayDependencies
    // The privacy screen belongs to the app (it is cross-cutting). We receive a builder
    // instead of depending on the app module: the dependency points inward.
    @ObservationIgnored private let makePrivacyView: @MainActor () -> AnyView

    public init(dependencies: TodayDependencies, makePrivacyView: @escaping @MainActor () -> AnyView) {
        self.dependencies = dependencies
        self.makePrivacyView = makePrivacyView
        self.viewModel = TodayViewModel(dependencies: dependencies)
        viewModel.router = self
    }

    // MARK: TodayRouting

    public func presentAddTask() { sheet = .addTask }
    public func presentPause(for task: FocusTask) { sheet = .pause(task) }
    public func presentPrivacy() { sheet = .privacy }
    public func dismissSheet() { sheet = nil }

    public func presentStepSuggestions(for task: FocusTask) {
        sheet = .steps(StepSuggestionsViewModel(
            task: task,
            suggester: dependencies.suggester,
            analytics: dependencies.analytics
        ))
    }

    // MARK: Screen factory

    @ViewBuilder
    func view(for sheet: Sheet) -> some View {
        switch sheet {
        case .addTask:
            AddTaskSheet(viewModel: viewModel)
        case .pause(let task):
            PauseSheet(task: task, viewModel: viewModel)
        case .steps(let stepsViewModel):
            StepSuggestionsSheet(viewModel: stepsViewModel) { step, source in
                await self.viewModel.acceptSuggestedStep(step, for: stepsViewModel.task, source: source)
            }
        case .privacy:
            makePrivacyView()
        }
    }
}

/// The feature's entry point for the app.
public struct TodayCoordinatorView: View {
    // `@State` keeps the coordinator alive while the view exists, even if the
    // parent's `body` is recomputed many times.
    @State private var coordinator: TodayCoordinator

    public init(coordinator: TodayCoordinator) {
        _coordinator = State(initialValue: coordinator)
    }

    public var body: some View {
        TodayView(viewModel: coordinator.viewModel)
            .sheet(item: $coordinator.sheet) { sheet in
                coordinator.view(for: sheet)
            }
    }
}
