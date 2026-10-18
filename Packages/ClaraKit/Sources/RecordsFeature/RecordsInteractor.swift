import ClaraCore
import ClaraServices
import Foundation

/// O que a View pode pedir ao Interactor.
@MainActor
protocol RecordsBusinessLogic: AnyObject {
    func load() async
    func save(_ draft: MomentDraft, editing id: UUID?) async -> MomentSaveResult
    func delete(id: UUID) async
}

/// Dados que o Router lê para montar a próxima tela (ex.: o momento a editar).
@MainActor
protocol RecordsDataStore: AnyObject {
    var moments: [Moment] { get }
}

/// Regras de negócio da tela. Não conhece UIKit nem formatação de texto:
/// recebe pedidos, fala com o repositório e entrega dados crus ao Presenter.
@MainActor
final class RecordsInteractor: RecordsBusinessLogic, RecordsDataStore {
    var presenter: (any RecordsPresentationLogic)?
    private(set) var moments: [Moment] = []

    private let repository: any MomentRepository
    private let analytics: any AnalyticsTracker
    private let crashReporter: any CrashReporter
    private let timeZone: @Sendable () -> TimeZone

    init(
        repository: any MomentRepository,
        analytics: any AnalyticsTracker,
        crashReporter: any CrashReporter,
        timeZone: @escaping @Sendable () -> TimeZone = { .current }
    ) {
        self.repository = repository
        self.analytics = analytics
        self.crashReporter = crashReporter
        self.timeZone = timeZone
    }

    func load() async {
        do {
            moments = try await repository.list()
            presenter?.presentMoments(Records.Load.Response(moments: moments))
        } catch is CancellationError {
            return
        } catch {
            crashReporter.record(error, context: "records.load")
            presenter?.presentFailure(title: "Não foi possível abrir os registros", message: "Seu histórico local continua no aparelho.")
        }
    }

    func save(_ draft: MomentDraft, editing id: UUID?) async -> MomentSaveResult {
        guard draft.hasContent else { return .needsContent }
        do {
            if let id, let original = moments.first(where: { $0.id == id }) {
                try await repository.update(original.applying(draft, currentTimeZone: timeZone()))
            } else {
                try await repository.create(draft)
            }
            analytics.track(.momentSaved(kind: draft.kind.rawValue, isEdit: id != nil))
            await load()
            return .saved
        } catch StorageError.conflict {
            // Alguém (outra tela, futuro sync) mudou o registro: recarrega em vez de sobrescrever.
            await load()
            presenter?.presentFailure(title: "Este registro mudou", message: "Abrimos a versão mais recente. Confira e edite de novo, se quiser.")
            return .failed
        } catch {
            crashReporter.record(error, context: "records.save")
            return .failed
        }
    }

    func delete(id: UUID) async {
        guard let moment = moments.first(where: { $0.id == id }) else { return }
        do {
            try await repository.delete(moment)
            analytics.track(.momentDeleted)
            await load()
        } catch {
            crashReporter.record(error, context: "records.delete")
            presenter?.presentFailure(title: "Não foi possível excluir", message: "Tente novamente.")
        }
    }
}
