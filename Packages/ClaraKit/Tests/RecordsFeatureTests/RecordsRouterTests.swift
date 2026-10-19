import ClaraCore
import ClaraStorage
import ClaraTestSupport
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import RecordsFeature

/// O Router com um ViewController espião: ele guarda o que seria apresentado em vez
/// de mostrar na tela, então nenhum teste precisa de janela.
@Suite("Registros — Router")
@MainActor
struct RecordsRouterTests {
    let viewController = PresentingSpy()
    let interactor = InteractorStub()
    let now = Fixtures.date("2026-10-10T12:00:00-03:00")

    func makeRouter() -> RecordsRouter {
        let router = RecordsRouter(now: { [now] in now })
        router.viewController = viewController
        router.dataStore = interactor
        router.interactor = interactor
        return router
    }

    func presentedForm() throws -> MomentFormView {
        let host = try #require(viewController.presented as? UIHostingController<MomentFormView>)
        return host.rootView
    }

    @Test("novo registro abre o formulário em modo de criação, sem datas no futuro")
    func newMomentOpensForm() throws {
        makeRouter().routeToNewMoment(kind: .daily)

        let form = try presentedForm()
        #expect(!form.isEditing)
        #expect(form.maximumDate == now)
    }

    @Test("editar abre o formulário em modo de edição")
    func editOpensForm() throws {
        let moment = Fixtures.moment(at: "2026-10-09T09:00:00-03:00", note: "antes")
        interactor.moments = [moment]

        makeRouter().routeToEdit(momentID: moment.id)

        #expect(try presentedForm().isEditing)
    }

    @Test("editar um registro que não existe mais não abre nada")
    func editMissingMomentDoesNothing() {
        makeRouter().routeToEdit(momentID: UUID())

        #expect(viewController.presented == nil)
    }

    @Test("salvar no formulário fecha a tela só quando deu certo")
    func saveDismissesOnlyOnSuccess() async throws {
        makeRouter().routeToNewMoment(kind: .daily)
        let form = try presentedForm()
        let draft = MomentDraft(kind: .daily, occurredAt: now, mood: .good)

        interactor.result = .needsContent
        #expect(await form.onSave(draft) == .needsContent)
        #expect(viewController.dismissCount == 0)

        interactor.result = .saved
        #expect(await form.onSave(draft) == .saved)
        #expect(viewController.dismissCount == 1)
        #expect(interactor.savedDrafts == [draft, draft])
    }

    @Test("excluir pede confirmação com a opção de manter")
    func deleteAsksForConfirmation() throws {
        makeRouter().routeToDeleteConfirmation(momentID: UUID())

        let alert = try #require(viewController.presented as? UIAlertController)
        #expect(alert.title == "Excluir este registro?")
        #expect(alert.actions.map(\.title) == ["Manter", "Excluir"])
        #expect(alert.actions.map(\.style) == [.cancel, .destructive])
    }
}

@Suite("Registros — Builder")
@MainActor
struct RecordsBuilderTests {
    @Test("liga as peças do VIP nos dois sentidos")
    func wiresTheCycle() throws {
        let dependencies = RecordsDependencies(
            repository: LocalMomentRepository(database: LocalDatabase(inMemory: .init())),
            analytics: SpyAnalyticsTracker(),
            crashReporter: SpyCrashReporter()
        )

        let viewController = try #require(RecordsBuilder.make(dependencies: dependencies) as? RecordsViewController)

        let interactor = try #require(viewController.interactor as? RecordsInteractor)
        let presenter = try #require(interactor.presenter as? RecordsPresenter)
        let router = try #require(viewController.router as? RecordsRouter)
        #expect(presenter.viewController === viewController)
        #expect(router.viewController === viewController)
        #expect(router.dataStore === interactor)
        #expect(router.interactor === interactor)
    }
}

final class PresentingSpy: UIViewController {
    private(set) var presented: UIViewController?
    private(set) var dismissCount = 0

    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        presented = viewControllerToPresent
    }

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        dismissCount += 1
    }
}

@MainActor
final class InteractorStub: RecordsBusinessLogic, RecordsDataStore {
    var moments: [Moment] = []
    var result: MomentSaveResult = .saved
    private(set) var savedDrafts: [MomentDraft] = []

    func load() async {}

    func save(_ draft: MomentDraft, editing id: UUID?) async -> MomentSaveResult {
        savedDrafts.append(draft)
        return result
    }

    func delete(id: UUID) async {}
}
