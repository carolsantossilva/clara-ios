import ClaraCore
import ClaraDesignSystem
import Observation
import SwiftUI

/// O "C" do MVVM-C: decide *como* navegar. O ViewModel só diz *o que* quer.
///
/// Vantagens: o ViewModel fica testável sem SwiftUI (os testes usam um router
/// espião) e o fluxo de telas da feature fica num lugar só.
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
    // Tela de privacidade pertence ao app (é transversal). Recebemos um construtor
    // em vez de depender do módulo do app — a dependência aponta para dentro.
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

    // MARK: Fábrica de telas

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

/// Ponto de entrada da feature para o app.
public struct TodayCoordinatorView: View {
    // `@State` mantém o coordinator vivo enquanto a view existir, mesmo que o
    // `body` do pai seja recalculado várias vezes.
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
