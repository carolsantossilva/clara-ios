import ClaraDesignSystem
import UIKit

/// A View Code cell with anchor-based Auto Layout.
///
/// Accessibility: VoiceOver reads the cell as a single element (full text)
/// and offers "Editar" (edit) and "Excluir" (delete) as custom actions (rotor), instead of
/// forcing navigation through each small button.
final class MomentCell: UITableViewCell {
    static let reuseIdentifier = "MomentCell"

    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?

    private let card = UIView()
    private let iconLabel = UILabel()
    private let moodTagLabel = PaddedLabel()
    private let dateLabel = UILabel()
    private let noteLabel = UILabel()
    private let contextLabel = UILabel()
    private let helpedLabel = UILabel()
    private let emptyNoteLabel = UILabel()
    private let editButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupHierarchy()
        setupStyle()
        setupConstraints()
        observeAppearanceChanges()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Use View Code")
    }

    // Cells are reused: clearing closures keeps a tap on a recycled cell from
    // running the old row's action.
    override func prepareForReuse() {
        super.prepareForReuse()
        onEdit = nil
        onDelete = nil
    }

    func configure(with row: Records.Row) {
        iconLabel.text = row.symbol
        moodTagLabel.text = row.moodTag
        dateLabel.text = row.dateLine
        set(noteLabel, row.note)
        set(contextLabel, row.context)
        set(helpedLabel, row.helpedOrHindered)
        set(emptyNoteLabel, row.emptyNote)
        accessibilityLabel = row.accessibilityLabel
        accessibilityIdentifier = "records.row"
    }

    private func set(_ label: UILabel, _ text: String?) {
        label.text = text
        // Inside a UIStackView, `isHidden` also removes the space it took.
        label.isHidden = text == nil
    }

    // MARK: Layout

    private let mainStack = UIStackView()

    private func setupHierarchy() {
        contentView.addSubview(card)
        card.addSubview(iconLabel)
        card.addSubview(mainStack)

        let metaStack = UIStackView(arrangedSubviews: [moodTagLabel, dateLabel])
        metaStack.axis = .horizontal
        metaStack.spacing = 7
        metaStack.alignment = .center

        let toolsStack = UIStackView(arrangedSubviews: [editButton, deleteButton, UIView()])
        toolsStack.axis = .horizontal
        toolsStack.spacing = 14

        [metaStack, noteLabel, contextLabel, helpedLabel, emptyNoteLabel, toolsStack].forEach(mainStack.addArrangedSubview)
        mainStack.axis = .vertical
        mainStack.spacing = 8
        mainStack.alignment = .fill
    }

    private func setupStyle() {
        backgroundColor = .clear
        selectionStyle = .none

        card.backgroundColor = ClaraPalette.paper
        card.layer.cornerRadius = 16
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = ClaraPalette.line.cgColor

        iconLabel.textAlignment = .center
        iconLabel.backgroundColor = ClaraPalette.lavender
        iconLabel.layer.cornerRadius = 10
        iconLabel.clipsToBounds = true

        moodTagLabel.font = ClaraFont.uiFont(.caption1, weight: .bold)
        moodTagLabel.textColor = ClaraPalette.lavenderDeep
        moodTagLabel.backgroundColor = ClaraPalette.lavender
        moodTagLabel.layer.cornerRadius = 10
        moodTagLabel.clipsToBounds = true
        moodTagLabel.setContentHuggingPriority(.required, for: .horizontal)
        // The date wraps over several lines; the tag must not be squeezed until its text disappears.
        moodTagLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        dateLabel.font = ClaraFont.uiFont(.caption1)
        dateLabel.textColor = ClaraPalette.muted
        dateLabel.numberOfLines = 0

        for label in [noteLabel, contextLabel, helpedLabel] {
            label.font = ClaraFont.uiFont(.subheadline)
            label.textColor = ClaraPalette.ink
            label.numberOfLines = 0
        }
        emptyNoteLabel.font = ClaraFont.uiFont(.footnote)
        emptyNoteLabel.textColor = ClaraPalette.muted
        emptyNoteLabel.numberOfLines = 0

        // Dynamic Type: fonts follow the size chosen in Settings.
        for label in [moodTagLabel, dateLabel, noteLabel, contextLabel, helpedLabel, emptyNoteLabel] as [UILabel] {
            label.adjustsFontForContentSizeCategory = true
        }

        configureTool(editButton, title: "Editar") { [weak self] in self?.onEdit?() }
        configureTool(deleteButton, title: "Excluir") { [weak self] in self?.onDelete?() }

        isAccessibilityElement = true
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Editar") { [weak self] _ in
                self?.onEdit?()
                return true
            },
            UIAccessibilityCustomAction(name: "Excluir") { [weak self] _ in
                self?.onDelete?()
                return true
            },
        ]
    }

    private func configureTool(_ button: UIButton, title: String, action: @escaping () -> Void) {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.baseForegroundColor = ClaraPalette.lavenderDeep
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)
        button.configuration = configuration
        button.scalesConfigurationFonts(title: .footnote, titleWeight: .bold)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
    }

    private func setupConstraints() {
        [card, iconLabel, mainStack].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),
            card.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),

            iconLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            iconLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            iconLabel.widthAnchor.constraint(equalToConstant: 28),
            iconLabel.heightAnchor.constraint(equalToConstant: 28),

            mainStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            mainStack.leadingAnchor.constraint(equalTo: iconLabel.trailingAnchor, constant: 10),
            mainStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            mainStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -4),
        ])
    }

    // `cgColor` is not dynamic: when switching light/dark, the border has to be redone.
    // iOS 17 traits API (replaces `traitCollectionDidChange`).
    private func observeAppearanceChanges() {
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (cell: MomentCell, _: UITraitCollection) in
            cell.card.layer.borderColor = ClaraPalette.line.resolvedColor(with: cell.traitCollection).cgColor
        }
    }
}

/// A UILabel with inner padding (for the "tags").
final class PaddedLabel: UILabel {
    var insets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
}
