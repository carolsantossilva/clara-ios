import ClaraCore
import ClaraStorage
import ClaraTestSupport
import Foundation
import Testing
@testable import RecordsFeature

/// Cada peça do VIP é testada isolada: o Interactor com um Presenter espião,
/// o Presenter com uma View espiã. Nenhum teste precisa de UIKit na tela.
@Suite("Registros — Interactor")
@MainActor
struct RecordsInteractorTests {
    let presenter = PresenterSpy()
    let analytics = SpyAnalyticsTracker()
    let crashReporter = SpyCrashReporter()

    func makeInteractor(repository: any MomentRepository) -> RecordsInteractor {
        let interactor = RecordsInteractor(repository: repository, analytics: analytics, crashReporter: crashReporter)
        interactor.presenter = presenter
        return interactor
    }

    @Test("rascunho vazio não é salvo")
    func emptyDraftNeedsContent() async {
        let repository = LocalMomentRepository(database: LocalDatabase(inMemory: .init()))
        let interactor = makeInteractor(repository: repository)

        let result = await interactor.save(MomentDraft(kind: .daily, occurredAt: .now), editing: nil)

        #expect(result == .needsContent)
        #expect(try await repository.list().isEmpty)
    }

    @Test("salvar cria o registro, recarrega a lista e registra evento")
    func saveCreatesAndReloads() async {
        let interactor = makeInteractor(repository: LocalMomentRepository(database: LocalDatabase(inMemory: .init())))

        let result = await interactor.save(MomentDraft(kind: .daily, occurredAt: .now, mood: .good), editing: nil)

        #expect(result == .saved)
        #expect(presenter.presentedMoments.last?.count == 1)
        #expect(analytics.events.last?.properties == ["kind": "daily", "is_edit": "false"])
    }

    @Test("editar atualiza o registro existente")
    func editUpdates() async throws {
        let repository = LocalMomentRepository(database: LocalDatabase(inMemory: .init()))
        let interactor = makeInteractor(repository: repository)
        _ = await interactor.save(MomentDraft(kind: .event, occurredAt: .now, note: "antes"), editing: nil)
        let original = try #require(interactor.moments.first)

        var draft = MomentDraft(editing: original)
        draft.note = "depois"
        let result = await interactor.save(draft, editing: original.id)

        #expect(result == .saved)
        #expect(try await repository.list().map(\.note) == ["depois"])
    }

    @Test("falha ao carregar apresenta erro amigável")
    func loadFailure() async {
        let interactor = makeInteractor(repository: FailingMomentRepository())

        await interactor.load()

        #expect(presenter.failures.first?.title == "Não foi possível abrir os registros")
        #expect(crashReporter.contexts == ["records.load"])
    }
}

@Suite("Registros — Presenter")
@MainActor
struct RecordsPresenterTests {
    @Test("formata a linha com rótulos e sem campos vazios")
    func formatsRow() {
        let moment = Fixtures.moment(
            kind: .daily,
            at: "2026-09-20T10:00:00-03:00",
            mood: .good,
            context: "noite curta"
        )

        let row = RecordsPresenter.makeRow(moment)

        #expect(row.moodTag == "Bem")
        #expect(row.symbol == "☀")
        #expect(row.dateLine.hasPrefix("Check-in · "))
        #expect(row.note == nil)
        #expect(row.context == "Contexto: noite curta")
        #expect(row.emptyNote == nil)
    }

    @Test("registro só com a palavra mostra a nota acolhedora")
    func moodOnly() {
        let row = RecordsPresenter.makeRow(Fixtures.moment(at: "2026-09-20T10:00:00-03:00", mood: .difficult))
        #expect(row.emptyNote == "Só a palavra escolhida — e tudo bem.")
    }

    @Test("entrega o ViewModel para a View")
    func forwardsToView() {
        let presenter = RecordsPresenter()
        let view = DisplaySpy()
        presenter.viewController = view

        presenter.presentMoments(.init(moments: [Fixtures.moment(at: "2026-09-20T10:00:00-03:00")]))

        #expect(view.displayed.first?.rows.count == 1)
    }
}

@MainActor
final class PresenterSpy: RecordsPresentationLogic {
    private(set) var presentedMoments: [[Moment]] = []
    private(set) var failures: [(title: String, message: String)] = []

    func presentMoments(_ response: Records.Load.Response) {
        presentedMoments.append(response.moments)
    }

    func presentFailure(title: String, message: String) {
        failures.append((title, message))
    }
}

@MainActor
final class DisplaySpy: RecordsDisplayLogic {
    private(set) var displayed: [Records.Load.ViewModel] = []
    private(set) var failures: [Records.Failure.ViewModel] = []

    func displayMoments(_ viewModel: Records.Load.ViewModel) { displayed.append(viewModel) }
    func displayFailure(_ viewModel: Records.Failure.ViewModel) { failures.append(viewModel) }
}
