import ClaraCore
import SwiftUI

// MARK: - Botões

/// Um `ButtonStyle` customizado: o botão continua sendo um `Button` nativo
/// (VoiceOver, foco de teclado, estados), só a aparência muda.
public struct ClaraButtonStyle: ButtonStyle {
    public enum Kind {
        case primary
        case secondary
    }

    let kind: Kind
    @Environment(\.isEnabled) private var isEnabled

    public init(kind: Kind) {
        self.kind = kind
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 46)
            .padding(.horizontal, 14)
            .foregroundStyle(kind == .primary ? ClaraColor.onLavenderDeep : ClaraColor.lavenderDeep)
            .background(
                kind == .primary ? ClaraColor.lavenderDeep : ClaraColor.lavender,
                in: RoundedRectangle(cornerRadius: ClaraRadius.control, style: .continuous)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.5)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == ClaraButtonStyle {
    public static var claraPrimary: ClaraButtonStyle { ClaraButtonStyle(kind: .primary) }
    public static var claraSecondary: ClaraButtonStyle { ClaraButtonStyle(kind: .secondary) }
}

// MARK: - Cartão

public struct ClaraCardModifier: ViewModifier {
    let background: Color
    let border: Color
    let radius: CGFloat

    public func body(content: Content) -> some View {
        content
            .padding(ClaraSpacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
    }
}

extension View {
    public func claraCard(
        background: Color = ClaraColor.paper,
        border: Color = ClaraColor.line,
        radius: CGFloat = 20
    ) -> some View {
        modifier(ClaraCardModifier(background: background, border: border, radius: radius))
    }
}

// MARK: - Textos

public struct EyebrowText: View {
    let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text.uppercased())
            .font(ClaraFont.eyebrow)
            .tracking(1.2)
            .foregroundStyle(ClaraColor.eyebrow)
    }
}

public struct SectionHeader<Trailing: View>: View {
    let eyebrow: String
    let title: String
    let trailing: Trailing

    public init(eyebrow: String, title: String, @ViewBuilder trailing: () -> Trailing) {
        self.eyebrow = eyebrow
        self.title = title
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .center, spacing: ClaraSpacing.small) {
            VStack(alignment: .leading, spacing: ClaraSpacing.extraSmall) {
                EyebrowText(eyebrow)
                Text(title)
                    .font(ClaraFont.headline)
                    .foregroundStyle(ClaraColor.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    public init(eyebrow: String, title: String) {
        self.init(eyebrow: eyebrow, title: title) { EmptyView() }
    }
}

public struct PageHeading: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    public init(eyebrow: String, title: String, subtitle: String) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ClaraSpacing.small) {
            EyebrowText(eyebrow)
            Text(title)
                .font(ClaraFont.largeTitle)
                .foregroundStyle(ClaraColor.ink)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(ClaraColor.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Campo de texto com rótulo

public struct LabeledTextField: View {
    let label: String
    let placeholder: String
    let isOptional: Bool
    let axis: Axis
    @Binding var text: String

    public init(_ label: String, text: Binding<String>, placeholder: String, isOptional: Bool = true, axis: Axis = .horizontal) {
        self.label = label
        self._text = text
        self.placeholder = placeholder
        self.isOptional = isOptional
        self.axis = axis
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            (Text(label).fontWeight(.semibold) + Text(isOptional ? " (opcional)" : "").foregroundColor(ClaraColor.muted))
                .font(.footnote)
                .foregroundStyle(ClaraColor.ink)
            TextField(placeholder, text: $text, axis: axis)
                .lineLimit(axis == .vertical ? 3...6 : 1...1)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(ClaraColor.paper, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(ClaraColor.line))
                .accessibilityLabel(label)
        }
    }
}

// MARK: - Seletor de humor

/// Três opções com rótulo e ícone: a informação nunca depende só da cor.
public struct MoodPicker: View {
    @Binding var selection: Mood?

    public init(selection: Binding<Mood?>) {
        self._selection = selection
    }

    public var body: some View {
        // ViewThatFits: em Dynamic Type muito grande, troca a linha por coluna.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: ClaraSpacing.small) { options }
            VStack(alignment: .leading, spacing: ClaraSpacing.small) { options }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Como foi para você?")
    }

    private var options: some View {
        ForEach(Mood.allCases, id: \.self) { mood in
            let isSelected = selection == mood
            Button {
                // Tocar de novo desmarca: escolher uma palavra é sempre opcional.
                selection = isSelected ? nil : mood
            } label: {
                HStack(spacing: 6) {
                    Text(mood.symbol).accessibilityHidden(true)
                    Text(mood.label).fontWeight(.semibold)
                }
                .font(.subheadline)
                .frame(minWidth: 84, minHeight: 44)
                .padding(.horizontal, 10)
                .foregroundStyle(ClaraColor.ink)
                .background(isSelected ? ClaraColor.lavender : ClaraColor.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isSelected ? ClaraColor.lavenderDeep : ClaraColor.line, lineWidth: isSelected ? 2 : 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier("mood.\(mood.rawValue)")
        }
    }
}

// MARK: - Estado vazio

public struct EmptyStateView: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: ClaraSpacing.small) {
            Text("✿")
                .font(.title)
                .frame(width: 44, height: 44)
                .background(ClaraColor.peach, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .accessibilityHidden(true)
            Text("Sua cabeça não precisa guardar tudo.")
                .font(ClaraFont.title)
                .foregroundStyle(ClaraColor.ink)
            Text("Escolha uma tarefa e transforme o começo em um passo pequeno.")
                .font(.subheadline)
                .foregroundStyle(ClaraColor.muted)
        }
        .padding(.vertical, ClaraSpacing.large)
    }
}

// MARK: - Marca

public struct BrandHeader<Badge: View>: View {
    let badge: Badge

    public init(@ViewBuilder badge: () -> Badge) {
        self.badge = badge()
    }

    public var body: some View {
        HStack {
            HStack(spacing: 9) {
                Text("c")
                    .font(.system(size: 26, design: .serif).italic())
                    .foregroundStyle(ClaraColor.onLavenderDeep)
                    .frame(width: 34, height: 34)
                    .background(ClaraColor.lavenderDeep, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    (Text("clara").foregroundColor(ClaraColor.ink) + Text(".").foregroundColor(ClaraColor.brandDot))
                        .font(.title3.weight(.heavy))
                    Text("um dia de cada vez")
                        .font(.caption2)
                        .foregroundStyle(ClaraColor.muted)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Clara, um dia de cada vez")
            Spacer()
            badge
        }
    }
}

public struct LocalOnlyBadge: View {
    public init() {}

    public var body: some View {
        HStack(spacing: 6) {
            Circle().fill(ClaraColor.sageInk).frame(width: 7, height: 7)
            Text("Só neste aparelho")
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(ClaraColor.sageInk)
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background(ClaraColor.sage, in: Capsule())
    }
}

// MARK: - Alerta

public struct AlertContent: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let title: String
    public let message: String

    public init(title: String, message: String) {
        self.title = title
        self.message = message
    }

    public static func == (lhs: AlertContent, rhs: AlertContent) -> Bool {
        lhs.title == rhs.title && lhs.message == rhs.message
    }
}

extension View {
    public func claraAlert(_ content: Binding<AlertContent?>) -> some View {
        alert(
            content.wrappedValue?.title ?? "",
            isPresented: Binding(
                get: { content.wrappedValue != nil },
                set: { if !$0 { content.wrappedValue = nil } }
            ),
            presenting: content.wrappedValue
        ) { _ in
            Button("Ok", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
    }
}
