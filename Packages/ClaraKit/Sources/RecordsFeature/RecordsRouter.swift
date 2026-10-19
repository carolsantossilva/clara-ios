import ClaraCore
import SwiftUI
import UIKit

@MainActor
protocol RecordsRoutingLogic: AnyObject {
    func routeToNewMoment(kind: Moment.Kind)
    func routeToEdit(momentID: UUID)
    func routeToDeleteConfirmation(momentID: UUID)
}

/// The feature's navigation. Here UIKit presents a SwiftUI screen
/// (`UIHostingController`): interoperability both ways in the same app.
@MainActor
final class RecordsRouter: RecordsRoutingLogic {
    weak var viewController: UIViewController?
    weak var dataStore: (any RecordsDataStore)?
    weak var interactor: (any RecordsBusinessLogic)?
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = { .now }) {
        self.now = now
    }

    func routeToNewMoment(kind: Moment.Kind) {
        presentForm(draft: MomentDraft(kind: kind, occurredAt: now()), editingID: nil)
    }

    func routeToEdit(momentID: UUID) {
        guard let moment = dataStore?.moments.first(where: { $0.id == momentID }) else { return }
        presentForm(draft: MomentDraft(editing: moment), editingID: moment.id)
    }

    func routeToDeleteConfirmation(momentID: UUID) {
        let alert = UIAlertController(
            title: "Excluir este registro?",
            message: "Ele será removido deste aparelho.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Manter", style: .cancel))
        alert.addAction(UIAlertAction(title: "Excluir", style: .destructive) { [weak self] _ in
            Task { await self?.interactor?.delete(id: momentID) }
        })
        viewController?.present(alert, animated: true)
    }

    private func presentForm(draft: MomentDraft, editingID: UUID?) {
        let form = MomentFormView(
            draft: draft,
            isEditing: editingID != nil,
            maximumDate: now(),
            onSave: { [weak self] draft in
                guard let interactor = self?.interactor else { return .failed }
                let result = await interactor.save(draft, editing: editingID)
                if result == .saved {
                    self?.viewController?.dismiss(animated: true)
                }
                return result
            },
            onClose: { [weak self] in
                self?.viewController?.dismiss(animated: true)
            }
        )
        let host = UIHostingController(rootView: form)
        host.sheetPresentationController?.detents = [.large()]
        host.sheetPresentationController?.prefersGrabberVisible = true
        viewController?.present(host, animated: true)
    }
}
