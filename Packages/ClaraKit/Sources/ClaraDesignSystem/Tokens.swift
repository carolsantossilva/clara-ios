import SwiftUI
import UIKit

// Tokens do Design System, portados de `theme/tokens.ts` do app React Native.
// A fonte da verdade é UIColor dinâmica (claro/escuro); SwiftUI e UIKit leem a
// mesma cor, então as duas camadas de UI nunca divergem.

public enum ClaraPalette {
    public static let background = UIColor.dynamic(light: 0xF8F5F1, dark: 0x1B1920)
    public static let paper = UIColor.dynamic(light: 0xFFFDF9, dark: 0x25222C)
    public static let ink = UIColor.dynamic(light: 0x292537, dark: 0xF2EFF6)
    public static let muted = UIColor.dynamic(light: 0x5A5564, dark: 0xB5AFBE)
    public static let eyebrow = UIColor.dynamic(light: 0x5E5270, dark: 0xB9ADCB)
    public static let lavender = UIColor.dynamic(light: 0xF0ECF8, dark: 0x332D40)
    public static let lavenderDeep = UIColor.dynamic(light: 0x69558A, dark: 0xC9BBE4)
    public static let onLavenderDeep = UIColor.dynamic(light: 0xFFFDF9, dark: 0x1B1920)
    public static let sage = UIColor.dynamic(light: 0xEEF4EF, dark: 0x25302A)
    public static let sageInk = UIColor.dynamic(light: 0x55705B, dark: 0xA9C7AE)
    public static let peach = UIColor.dynamic(light: 0xFBEDE6, dark: 0x3A2C27)
    public static let sunshine = UIColor.dynamic(light: 0xFAF1DD, dark: 0x3A3324)
    public static let line = UIColor.dynamic(light: 0xE9E3E7, dark: 0x3A3541)
    public static let brandDot = UIColor.dynamic(light: 0xDF9F73, dark: 0xE8B08A)
}

public enum ClaraColor {
    public static let background = Color(uiColor: ClaraPalette.background)
    public static let paper = Color(uiColor: ClaraPalette.paper)
    public static let ink = Color(uiColor: ClaraPalette.ink)
    public static let muted = Color(uiColor: ClaraPalette.muted)
    public static let eyebrow = Color(uiColor: ClaraPalette.eyebrow)
    public static let lavender = Color(uiColor: ClaraPalette.lavender)
    public static let lavenderDeep = Color(uiColor: ClaraPalette.lavenderDeep)
    public static let onLavenderDeep = Color(uiColor: ClaraPalette.onLavenderDeep)
    public static let sage = Color(uiColor: ClaraPalette.sage)
    public static let sageInk = Color(uiColor: ClaraPalette.sageInk)
    public static let peach = Color(uiColor: ClaraPalette.peach)
    public static let sunshine = Color(uiColor: ClaraPalette.sunshine)
    public static let line = Color(uiColor: ClaraPalette.line)
    public static let brandDot = Color(uiColor: ClaraPalette.brandDot)
}

public enum ClaraRadius {
    public static let card: CGFloat = 24
    public static let control: CGFloat = 14
    public static let small: CGFloat = 10
}

public enum ClaraSpacing {
    public static let extraSmall: CGFloat = 4
    public static let small: CGFloat = 8
    public static let medium: CGFloat = 12
    public static let large: CGFloat = 18
    public static let extraLarge: CGFloat = 28
}

/// Tipografia baseada em estilos de texto: tudo acompanha o Dynamic Type.
/// Evite `caption2`: ele já está no tamanho mínimo (11 pt) no tamanho padrão e não
/// diminui com o ajuste do sistema; a auditoria de acessibilidade aponta isso.
public enum ClaraFont {
    public static let largeTitle = Font.system(.largeTitle, design: .serif)
    public static let title = Font.system(.title2, design: .serif)
    public static let headline = Font.system(.title3, design: .serif)
    public static let eyebrow = Font.caption.weight(.heavy)

    /// Versão UIKit. Cria a fonte no tamanho base e escala com `UIFontMetrics`, para
    /// que `adjustsFontForContentSizeCategory` funcione também com fonte serifada.
    /// `traits`: escala para o tamanho de texto dessa tela; sem ele, usa o do app.
    public static func uiFont(
        _ style: UIFont.TextStyle,
        serif: Bool = false,
        weight: UIFont.Weight? = nil,
        compatibleWith traits: UITraitCollection? = nil
    ) -> UIFont {
        let base = UITraitCollection(preferredContentSizeCategory: .large)
        var descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: style, compatibleWith: base)
        if serif, let serifDescriptor = descriptor.withDesign(.serif) {
            descriptor = serifDescriptor
        }
        if let weight {
            descriptor = descriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
        }
        return UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont(descriptor: descriptor, size: 0), compatibleWith: traits)
    }
}

extension UIButton {
    /// Fontes de um botão com `UIButton.Configuration` que acompanham o Dynamic Type.
    ///
    /// Botão com configuração não tem `adjustsFontForContentSizeCategory`, e o
    /// transformer de atributos não enxerga as traits do botão. O update handler
    /// enxerga: a fonte é refeita com o tamanho de texto da tela sempre que ele muda.
    public func scalesConfigurationFonts(
        title: UIFont.TextStyle,
        titleWeight: UIFont.Weight? = nil,
        subtitle: UIFont.TextStyle? = nil,
        subtitleColor: UIColor? = nil
    ) {
        configurationUpdateHandler = { button in
            guard var configuration = button.configuration else { return }
            let titleFont = ClaraFont.uiFont(title, weight: titleWeight, compatibleWith: button.traitCollection)
            // Atributo acessado pelo tipo: o key path de `updated.font` não é Sendable no transformer.
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var updated = attributes
                updated[AttributeScopes.UIKitAttributes.FontAttribute.self] = titleFont
                return updated
            }
            if let subtitle {
                let subtitleFont = ClaraFont.uiFont(subtitle, compatibleWith: button.traitCollection)
                configuration.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                    var updated = attributes
                    updated[AttributeScopes.UIKitAttributes.FontAttribute.self] = subtitleFont
                    if let subtitleColor {
                        updated[AttributeScopes.UIKitAttributes.ForegroundColorAttribute.self] = subtitleColor
                    }
                    return updated
                }
            }
            button.configuration = configuration
        }
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (button: UIButton, _: UITraitCollection) in
            button.setNeedsUpdateConfiguration()
        }
    }
}

extension UIColor {
    public convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    public static func dynamic(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        }
    }
}
