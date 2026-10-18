import ClaraCore
import ClaraServices
import SwiftUI
import UIKit

public struct RecordsDependencies: Sendable {
    public var repository: any MomentRepository
    public var analytics: any AnalyticsTracker
    public var crashReporter: any CrashReporter

    public init(repository: any MomentRepository, analytics: any AnalyticsTracker, crashReporter: any CrashReporter) {
        self.repository = repository
        self.analytics = analytics
        self.crashReporter = crashReporter
    }
}

/// Monta o ciclo VIP e liga as referências (fortes num sentido, fracas no outro):
///
///     ViewController ──▶ Interactor ──▶ Presenter ┄┄▶ ViewController (weak)
///           │
///           └──▶ Router ┄┄▶ ViewController / Interactor (weak)
public enum RecordsBuilder {
    @MainActor
    public static func make(dependencies: RecordsDependencies) -> UIViewController {
        let viewController = RecordsViewController()
        let interactor = RecordsInteractor(
            repository: dependencies.repository,
            analytics: dependencies.analytics,
            crashReporter: dependencies.crashReporter
        )
        let presenter = RecordsPresenter()
        let router = RecordsRouter()

        viewController.interactor = interactor
        viewController.router = router
        interactor.presenter = presenter
        presenter.viewController = viewController
        router.viewController = viewController
        router.dataStore = interactor
        router.interactor = interactor
        return viewController
    }
}

/// Ponte para usar a tela UIKit dentro da navegação SwiftUI (TabView do app).
public struct RecordsScreen: UIViewControllerRepresentable {
    private let dependencies: RecordsDependencies

    public init(dependencies: RecordsDependencies) {
        self.dependencies = dependencies
    }

    public func makeUIViewController(context: Context) -> UIViewController {
        RecordsBuilder.make(dependencies: dependencies)
    }

    public func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
