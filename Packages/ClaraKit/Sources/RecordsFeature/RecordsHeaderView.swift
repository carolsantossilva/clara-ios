import ClaraDesignSystem
import UIKit

/// Cabeçalho da tela: título e os dois atalhos (check-in e momento avulso).
final class RecordsHeaderView: UIView {
    var onCheckIn: (() -> Void)?
    var onNewMoment: (() -> Void)?

    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Use View Code")
    }

    private func setup() {
        let eyebrow = UILabel()
        eyebrow.text = "SEUS REGISTROS, DO SEU JEITO"
        eyebrow.font = ClaraFont.uiFont(.caption2, weight: .heavy)
        eyebrow.textColor = ClaraPalette.eyebrow

        let title = UILabel()
        title.text = "Como você tem estado?"
        title.font = ClaraFont.uiFont(.largeTitle, serif: true)
        title.textColor = ClaraPalette.ink
        title.numberOfLines = 0
        title.accessibilityTraits = .header

        let subtitle = UILabel()
        subtitle.text = "Anote só o que fizer sentido para você."
        subtitle.font = ClaraFont.uiFont(.subheadline)
        subtitle.textColor = ClaraPalette.muted
        subtitle.numberOfLines = 0

        let checkIn = makeActionButton(
            ActionContent(
                title: "Check-in de hoje",
                subtitle: "Uma palavra já basta. Também pode pular.",
                symbol: "sun.max"
            ),
            background: ClaraPalette.sunshine,
            identifier: "records.checkIn"
        ) { [weak self] in self?.onCheckIn?() }

        let moment = makeActionButton(
            ActionContent(
                title: "Registrar um momento",
                subtitle: "Bom, difícil ou algo que queira lembrar.",
                symbol: "sparkle"
            ),
            background: ClaraPalette.lavender,
            identifier: "records.newMoment"
        ) { [weak self] in self?.onNewMoment?() }

        let timelineTitle = UILabel()
        timelineTitle.text = "O que você escolheu guardar"
        timelineTitle.font = ClaraFont.uiFont(.title3, serif: true)
        timelineTitle.textColor = ClaraPalette.ink
        timelineTitle.numberOfLines = 0
        timelineTitle.accessibilityTraits = .header

        for label in [eyebrow, title, subtitle, timelineTitle] {
            label.adjustsFontForContentSizeCategory = true
        }

        [eyebrow, title, subtitle, checkIn, moment, timelineTitle].forEach(stack.addArrangedSubview)
        stack.axis = .vertical
        stack.spacing = 10
        stack.setCustomSpacing(20, after: subtitle)
        stack.setCustomSpacing(28, after: moment)

        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        // Prioridade 999 no fundo: antes do primeiro cálculo de tamanho o frame é
        // zero, e uma restrição obrigatória geraria avisos de conflito no console.
        let bottom = stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        bottom.priority = .init(999)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            bottom,
        ])
    }

    /// Texto e ícone de um botão de ação do cabeçalho.
    private struct ActionContent {
        let title: String
        let subtitle: String
        let symbol: String
    }

    private func makeActionButton(
        _ content: ActionContent,
        background: UIColor,
        identifier: String,
        action: @escaping () -> Void
    ) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.title = content.title
        configuration.subtitle = content.subtitle
        configuration.image = UIImage(systemName: content.symbol)
        configuration.imagePlacement = .leading
        configuration.imagePadding = 12
        configuration.titleAlignment = .leading
        configuration.titlePadding = 4
        configuration.baseBackgroundColor = background
        configuration.baseForegroundColor = ClaraPalette.ink
        configuration.cornerStyle = .large
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 14, bottom: 16, trailing: 14)
        // Atributo acessado pelo tipo: o key path de `updated.font` não é Sendable no transformer.
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var updated = attributes
            updated[AttributeScopes.UIKitAttributes.FontAttribute.self] = ClaraFont.uiFont(.subheadline, weight: .bold)
            return updated
        }
        configuration.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var updated = attributes
            updated[AttributeScopes.UIKitAttributes.FontAttribute.self] = ClaraFont.uiFont(.footnote)
            updated[AttributeScopes.UIKitAttributes.ForegroundColorAttribute.self] = ClaraPalette.muted
            return updated
        }

        let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
        button.contentHorizontalAlignment = .leading
        button.accessibilityIdentifier = identifier
        return button
    }
}
