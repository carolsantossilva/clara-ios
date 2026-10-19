import ClaraDesignSystem
import UIKit

@MainActor
protocol RecordsDisplayLogic: AnyObject {
    func displayMoments(_ viewModel: Records.Load.ViewModel)
    func displayFailure(_ viewModel: Records.Failure.ViewModel)
}

/// The Records screen in UIKit + View Code (no storyboard).
///
/// Lifecycle that matters here:
/// - `loadView`: creates the view hierarchy (instead of a storyboard).
/// - `viewDidLoad`: one-time setup + first load.
/// - `viewDidLayoutSubviews`: final sizes exist; we recompute the table header
///   height, which UITableView does not size on its own.
final class RecordsViewController: UIViewController, RecordsDisplayLogic {
    var interactor: (any RecordsBusinessLogic)?
    var router: (any RecordsRoutingLogic)?

    private enum Section { case timeline }

    /// Items identified by ID, not by the whole row: when a record is edited,
    /// the cell is *reconfigured* instead of removed and inserted again.
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
        // The Task inherits the view controller's MainActor. `[weak self]` keeps the
        // load from holding the screen alive if it is closed before finishing.
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
        // Reassigning is how you tell the table that the header changed height.
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
        // Honors "Reduce Motion" and does not animate before the screen is visible.
        let animate = view.window != nil && !UIAccessibility.isReduceMotionEnabled
        dataSource.apply(snapshot, animatingDifferences: animate)
    }

    func displayFailure(_ viewModel: Records.Failure.ViewModel) {
        let alert = UIAlertController(title: viewModel.title, message: viewModel.message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Ok", style: .cancel))
        present(alert, animated: true)
    }
}
