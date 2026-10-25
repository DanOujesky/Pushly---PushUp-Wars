import SwiftUI

/// Cosmetics catalog (D-074, shared/cosmetics/cosmetics.json): Pro profile frames and clan badges. Cosmetic only —
/// nothing here changes reps, trophies, matchmaking, wars or leaderboards. Same as Android `Cosmetics`.
public enum Cosmetics {
    /// Pro profile frames, in shop order.
    public static let frames = ["gold", "neon", "fire", "ice", "royal"]

    public static let badgeShapes = ["shield", "round", "hex"]
    public static let badgeColors = ["flame", "volt", "cyan", "lime", "gold", "red", "diamond", "pink"]

    public struct Emblem: Hashable, Sendable, Identifiable {
        public let id: String
        public let glyph: String
        public let pro: Bool
    }

    public static let emblems: [Emblem] = [
        Emblem(id: "flame", glyph: "🔥", pro: false), Emblem(id: "fist", glyph: "👊", pro: false),
        Emblem(id: "bolt", glyph: "⚡", pro: false), Emblem(id: "muscle", glyph: "💪", pro: false),
        Emblem(id: "wolf", glyph: "🐺", pro: false), Emblem(id: "lion", glyph: "🦁", pro: false),
        Emblem(id: "eagle", glyph: "🦅", pro: false), Emblem(id: "skull", glyph: "💀", pro: false),
        Emblem(id: "dragon", glyph: "🐉", pro: true), Emblem(id: "crown", glyph: "👑", pro: true),
        Emblem(id: "diamond", glyph: "💎", pro: true), Emblem(id: "rocket", glyph: "🚀", pro: true),
        Emblem(id: "trident", glyph: "🔱", pro: true), Emblem(id: "shark", glyph: "🦈", pro: true),
        Emblem(id: "comet", glyph: "☄️", pro: true), Emblem(id: "volcano", glyph: "🌋", pro: true),
    ]

    public static func emblem(_ id: String?) -> Emblem? { emblems.first { $0.id == id } }

    public static func badgeColor(_ id: String) -> TokenColor {
        switch id {
        case "volt": ColorTokens.brandVolt
        case "cyan": ColorTokens.brandCyan
        case "lime": ColorTokens.brandLime
        case "gold": ColorTokens.leagueGold
        case "red": ColorTokens.stateDanger
        case "diamond": ColorTokens.leagueDiamond
        case "pink": ColorTokens.leagueChampion
        default: ColorTokens.brandFlame
        }
    }

    /// Gradient stops of a frame (nil = no frame).
    public static func frameColors(_ id: String?) -> [TokenColor]? {
        switch id {
        case "gold": [ColorTokens.leagueGold, ColorTokens.brandFlame, ColorTokens.leagueGold, ColorTokens.leagueSilver, ColorTokens.leagueGold]
        case "neon": [ColorTokens.brandCyan, ColorTokens.brandVolt, ColorTokens.brandLime, ColorTokens.brandCyan]
        case "fire": [ColorTokens.brandFlame, ColorTokens.stateDanger, ColorTokens.leagueGold, ColorTokens.brandFlame]
        case "ice": [ColorTokens.leagueDiamond, ColorTokens.leagueSilver, ColorTokens.brandCyan, ColorTokens.leagueDiamond]
        case "royal": [ColorTokens.brandVolt, ColorTokens.leagueChampion, ColorTokens.leagueGold, ColorTokens.brandVolt]
        default: nil
        }
    }
}

/// A clan's badge: shape + colour + emblem. `{}` (older clans) gets a stable look from the tag.
public struct ClanBadgeStyle: Codable, Hashable, Sendable {
    public var shape: String?
    public var color: String?
    public var emblem: String?

    public init(shape: String? = nil, color: String? = nil, emblem: String? = nil) {
        self.shape = shape
        self.color = color
        self.emblem = emblem
    }

    /// The badge as drawn: missing parts are picked from the tag, so every clan looks different and stays the same.
    public func resolved(tag: String) -> (shape: String, color: String, emblem: Cosmetics.Emblem) {
        let seed = ClanBadgeStyle.seed(tag)
        let free = Cosmetics.emblems.filter { !$0.pro }
        let shape = shape.flatMap { Cosmetics.badgeShapes.contains($0) ? $0 : nil } ?? "shield"
        let color = color.flatMap { Cosmetics.badgeColors.contains($0) ? $0 : nil }
            ?? Cosmetics.badgeColors[seed % Cosmetics.badgeColors.count]
        let emblem = Cosmetics.emblem(emblem) ?? free[(seed / 8) % free.count]
        return (shape, color, emblem)
    }

    /// Sum of the tag's Unicode scalars (same on Android).
    public static func seed(_ tag: String) -> Int {
        tag.uppercased().unicodeScalars.reduce(0) { $0 + Int($1.value) }
    }

    /// The patch for `update_clan` / `create_clan`.
    public var json: [String: String] {
        var out: [String: String] = [:]
        if let shape { out["shape"] = shape }
        if let color { out["color"] = color }
        if let emblem { out["emblem"] = emblem }
        return out
    }
}

/// A clan badge — a shield, round or hex in the clan's colour with its emblem. Static.
public struct ClanEmblemView: View {
    let style: ClanBadgeStyle
    let tag: String
    let size: CGFloat

    public init(style: ClanBadgeStyle?, tag: String, size: CGFloat = 56) {
        self.style = style ?? ClanBadgeStyle()
        self.tag = tag
        self.size = size
    }

    public var body: some View {
        let r = style.resolved(tag: tag)
        let color = Color(Cosmetics.badgeColor(r.color))
        ZStack {
            BadgeShape(kind: r.shape)
                .fill(LinearGradient(colors: [color, color.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                .shadow(color: color.opacity(0.45), radius: size * 0.12)
            BadgeShape(kind: r.shape)
                .inset(by: size * 0.06)
                .stroke(.white.opacity(0.35), lineWidth: max(1, size * 0.025))
            BadgeShape(kind: r.shape)
                .stroke(.black.opacity(0.35), lineWidth: max(1, size * 0.02))
            Text(verbatim: r.emblem.glyph)
                .font(.system(size: size * 0.46))
                .shadow(color: .black.opacity(0.4), radius: size * 0.03, y: size * 0.02)
                .offset(y: r.shape == "shield" ? -size * 0.04 : 0)
        }
        .frame(width: size, height: size * (r.shape == "shield" ? 1.12 : 1))
        .accessibilityHidden(true)
    }
}

/// Shield / circle / hexagon used by clan badges.
public struct BadgeShape: InsettableShape {
    let kind: String
    var insetAmount: CGFloat = 0

    public init(kind: String) { self.kind = kind }

    public func inset(by amount: CGFloat) -> BadgeShape {
        var s = self
        s.insetAmount += amount
        return s
    }

    public func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        switch kind {
        case "round":
            return Path(ellipseIn: r)
        case "hex":
            var p = Path()
            for i in 0..<6 {
                let a = CGFloat(i) * .pi / 3 - .pi / 2
                let pt = CGPoint(x: r.midX + r.width / 2 * cos(a), y: r.midY + r.height / 2 * sin(a))
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
            return p
        default:
            // shield: flat top with rounded shoulders, sides curving into a point
            var p = Path()
            let w = r.width, h = r.height, x = r.minX, y = r.minY
            p.move(to: CGPoint(x: x + w * 0.5, y: y))
            p.addQuadCurve(to: CGPoint(x: x + w, y: y + h * 0.1), control: CGPoint(x: x + w * 0.8, y: y + h * 0.1))
            p.addLine(to: CGPoint(x: x + w, y: y + h * 0.45))
            p.addQuadCurve(to: CGPoint(x: x + w * 0.5, y: y + h), control: CGPoint(x: x + w * 0.95, y: y + h * 0.82))
            p.addQuadCurve(to: CGPoint(x: x, y: y + h * 0.45), control: CGPoint(x: x + w * 0.05, y: y + h * 0.82))
            p.addLine(to: CGPoint(x: x, y: y + h * 0.1))
            p.addQuadCurve(to: CGPoint(x: x + w * 0.5, y: y), control: CGPoint(x: x + w * 0.2, y: y + h * 0.1))
            p.closeSubpath()
            return p
        }
    }
}

/// A Pro frame around an avatar (static gradient ring + soft glow).
public struct ProfileFrameRing: View {
    let frame: String?
    let size: CGFloat

    public init(frame: String?, size: CGFloat) {
        self.frame = frame
        self.size = size
    }

    public var body: some View {
        if let stops = Cosmetics.frameColors(frame) {
            let colors = stops.map { Color($0) }
            RoundedRectangle(cornerRadius: size * 0.34, style: .continuous)
                .strokeBorder(AngularGradient(colors: colors, center: .center), lineWidth: max(2, size * 0.075))
                .shadow(color: colors[0].opacity(0.6), radius: size * 0.1)
                .accessibilityHidden(true)
        }
    }
}
