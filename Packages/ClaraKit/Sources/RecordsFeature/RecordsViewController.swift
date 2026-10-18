import ClaraDesignSystem
import UIKit

@MainActor
protocol RecordsDisplayLogic: AnyObject {
    func displayMoments(_ viewModel: Records.Load.ViewModel)
    func displayFailure(_ viewModel: Records.Failure.ViewModel)
}

/// Tela de Registros em UIKit + View Code (sem storyboard).
///
/// Ciclo de vida relevante aqui:
/// - `loadView`: cria a hierarquia de views (no lugar do storyboard).
/// - `viewDidLoad`: configuração única + primeira carga.
/// - `viewDidLayoutSubviews`: os tamanhos finais já existem; recalculamos a
///   altura do cabeçalho da tabela, que o UITableView não dimensiona sozinho.
final class RecordsViewController: UIViewController, RecordsDisplayLogic {
    var interactor: (any RecordsBusinessLogic)?
    var router: (any RecordsRoutingLogic)?

    private enum Section { case timeline }

    /// Itens identificados por ID, não pela linha inteira: quando um registro é
    /// editado, a célula é *reconfigurada* em vez de removida e inserida de novo.
    private enum Item: Hashable {
        case moment(UUID)
        case empty
    }

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let headerView = RecordsHeaderView()
    private var rowsByID: [UUID: Records.Row] = [:]
    private lazy var dataSource = makeDataSource()

    override func loadView() {
        view = UIView()
        view.backgroundColor = ClaraPalette.background
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureTable()
        headerView.onCheckIn = { [weak self] in self?.router?.routeToNewMoment(kind: .daily) }
        headerView.onNewMoment = { [weak self] in self?.router?.routeToNewMoment(kind: .event) }
        // A Task herda o MainActor da view controller. `[weak self]` evita que a
        // carga mantenha a tela viva se ela for fechada antes de terminar.
        Task { [weak self] in await self?.interactor?.load() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        sizeHeaderToFit()
    }

    private func configureTable() {
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.allowsSelection = false
        tableView.register(MomentCell.self, forCellReuseIdentifier: MomentCell.reuseIdentifier)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "empty")
        tableView.tableHeaderView = headerView
        tableView.dataSource = dataSource
        tableView.accessibilityIdentifier = "records.table"
    }

    private func sizeHeaderToFit() {
        let width = tableView.bounds.width
        guard width > 0 else { return }
        let fitting = headerView.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        guard headerView.frame.height != fitting.height || headerView.frame.width != width else { return }
        headerView.frame.size = CGSize(width: width, height: fitting.height)
        // Reatribuir é o jeito de avisar a tabela que o cabeçalho mudou de altura.
        tableView.tableHeaderView = headerView
    }

    private func makeDataSource() -> UITableViewDiffableDataSource<Section, Item> {
        UITableViewDiffableDataSource(tableView: tableView) { [weak self] tableView, indexPath, item in
            switch item {
            case .moment(let id):
                guard let cell = tableView.dequeueReusableCell(withIdentifier: MomentCell.reuseIdentifier, for: indexPath) as? MomentCell,
                      let row = self?.rowsByID[id]
                else { return UITableViewCell() }
                cell.configure(with: row)
                cell.onEdit = { [weak self] in self?.router?.routeToEdit(momentID: id) }
                cell.onDelete = { [weak self] in self?.router?.routeToDeleteConfirmation(momentID: id) }
                return cell
            case .empty:
                let cell = tableView.dequeueReusableCell(withIdentifier: "empty", for: indexPath)
                var content = cell.defaultContentConfiguration()
                content.text = "☁\nAqui aparecem só os momentos que você decidir guardar."
                content.textProperties.alignment = .center
                content.textProperties.color = ClaraPalette.muted
                content.textProperties.font = ClaraFont.uiFont(.footnote)
                cell.contentConfiguration = content
                cell.backgroundColor = .clear
                return cell
            }
        }
    }

    // MARK: RecordsDisplayLogic

    func displayMoments(_ viewModel: Records.Load.ViewModel) {
        let previous = rowsByID
        rowsByID = Dictionary(uniqueKeysWithValues: viewModel.rows.map { ($0.id, $0) })

        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.timeline])
        if viewModel.rows.isEmpty {
            snapshot.appendItems([.empty])
        } else {
            snapshot.appendItems(viewModel.rows.map { .moment($0.id) })
            let changed = viewModel.rows
                .filter { previous[$0.id] != nil && previous[$0.id] != $0 }
                .map { Item.moment($0.id) }
            snapshot.reconfigureItems(changed)
        }
        // Respeita "Reduzir movimento" e não anima antes da tela estar visível.
        let animate = view.window != nil && !UIAccessibility.isReduceMotionEnabled
        dataSource.apply(snapshot, animatingDifferences: animate)
    }

    func displayFailure(_ viewModel: Records.Failure.ViewModel) {
        let alert = UIAlertController(title: viewModel.title, message: viewModel.message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Ok", style: .cancel))
        present(alert, animated: true)
    }
}
