import CoreText
import SwiftUI
import UIKit

// Hand-written bridges from the generated tokens (Generated/DesignTokens.swift) to SwiftUI.

public extension Color {
    /// A dynamic color that resolves to the token's light or dark value.
    init(_ token: TokenColor) {
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? token.dark : token.light)
        })
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

public extension LinearGradient {
    init(_ token: TokenGradient) {
        let radians = token.angleDegrees * .pi / 180
        let dx = cos(radians) / 2, dy = sin(radians) / 2
        self.init(
            colors: token.stops.map { Color($0) },
            startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy),
            endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 + dy)
        )
    }
}

/// Registers the bundled fonts (Barlow Condensed + Figtree, SIL OFL — see shared/design-tokens/fonts).
public enum PushlyFonts {
    private static let registered: Bool = {
        var ok = true
        for name in TypographyTokens.bundledFonts {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts") else {
                ok = false
                continue
            }
            // Fails harmlessly if already registered (e.g. in previews).
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return ok
    }()

    /// Idempotent; called automatically by `Font.token`. Returns false if a font file is missing from the bundle.
    @discardableResult
    public static func register() -> Bool { registered }
}

public extension Font {
    /// Font for a type token. Every token scales with Dynamic Type via its text style (CLAUDE.md §8).
    static func token(_ t: TypeToken) -> Font {
        PushlyFonts.register()
        return .custom(t.fontName, size: t.size, relativeTo: Font.TextStyle(t.textStyle))
    }

    /// The token's typeface at a fixed size that ignores Dynamic Type (only for graphics such as avatar initials).
    static func token(_ t: TypeToken, fixedSize: CGFloat) -> Font {
        PushlyFonts.register()
        return .custom(t.fontName, fixedSize: fixedSize)
    }
}

public extension View {
    /// Applies a type token completely: font, tracking, uppercase and line height.
    func typography(_ t: TypeToken) -> some View {
        modifier(TypographyModifier(token: t))
    }
}

private struct TypographyModifier: ViewModifier {
    let token: TypeToken
    @ScaledMetric private var scale: CGFloat = 1

    init(token: TypeToken) {
        self.token = token
        _scale = ScaledMetric(wrappedValue: 1, relativeTo: Font.TextStyle(token.textStyle))
    }

    func body(content: Content) -> some View {
        let size = token.size * scale
        // SwiftUI has no absolute line height; negative spacing is clamped to 0, which is fine for tight display type.
        let natural = size * 1.2
        content
            .font(.token(token))
            .tracking(token.tracking * size)
            .textCase(token.uppercase ? .uppercase : nil)
            .lineSpacing(max(0, token.lineHeight * scale - natural))
    }
}

extension Font.TextStyle {
    init(_ style: TokenTextStyle) {
        self = switch style {
        case .largeTitle: .largeTitle
        case .title: .title
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .body: .body
        case .subheadline: .subheadline
        case .footnote: .footnote
        case .caption: .caption
        case .caption2: .caption2
        }
    }
}

public enum Glow {
    /// Shadow under gradient CTAs and the logo mark.
    public static let flame = Color(ColorTokens.brandFlame).opacity(0.30)
}
