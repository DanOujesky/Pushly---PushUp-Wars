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

public extension Font {
    /// Font for a type token. Every token scales with Dynamic Type via its text style (CLAUDE.md §8).
    static func token(_ t: TypeToken) -> Font {
        let weight: Font.Weight = switch t.weight {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .extraBold: .heavy
        }
        let style = Font.TextStyle(t.textStyle)
        switch t.family {
        case .display:
            return .custom(TypographyTokens.displayFontName, size: t.size, relativeTo: style).weight(weight)
        case .system:
            // Token sizes equal Apple's default text style sizes, so the system style is used directly.
            return .system(style, weight: weight)
        }
    }
}

extension Font.TextStyle {
    init(_ style: TokenTextStyle) {
        self = switch style {
        case .largeTitle: .largeTitle
        case .title: .title
        case .title2: .title2
        case .headline: .headline
        case .body: .body
        case .subheadline: .subheadline
        case .caption: .caption
        case .caption2: .caption2
        }
    }
}
