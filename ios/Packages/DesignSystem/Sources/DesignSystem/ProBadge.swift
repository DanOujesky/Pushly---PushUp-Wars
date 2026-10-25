import SwiftUI

/// The gold PRO badge (Pushly Pro, D-073) — next to Pro users' names and on the paywall.
public struct ProBadge: View {
    public enum Size: Sendable { case small, regular, large }
    let size: Size

    public init(size: Size = .small) { self.size = size }

    public var body: some View {
        Text(verbatim: "PRO")
            .typography(size == .large ? TypographyTokens.titleS : TypographyTokens.tab)
            .foregroundStyle(Color(ColorTokens.bgBase))
            .padding(.horizontal, size == .small ? 5 : 8)
            .padding(.vertical, size == .small ? 1 : 3)
            .background(LinearGradient(colors: [Color(ColorTokens.leagueGold), Color(ColorTokens.brandFlame)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityLabel(Text("Pushly Pro"))
    }
}
