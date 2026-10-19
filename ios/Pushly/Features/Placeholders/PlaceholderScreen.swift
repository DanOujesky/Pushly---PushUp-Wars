import DesignSystem
import SwiftUI

/// Temporary tab content until each feature is built (roadmap P0-08).
struct PlaceholderScreen: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let symbol: String
    let glow: TokenColor

    var body: some View {
        NavigationStack {
            VStack(spacing: SpacingTokens.l) {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color(ColorTokens.bgSurface))
                    .stroke(Color(ColorTokens.strokeSubtle), lineWidth: 1)
                    .frame(width: 104, height: 104)
                    .overlay {
                        Image(systemName: symbol)
                            .font(.system(size: 44, weight: .bold))
                            .foregroundStyle(Color(glow))
                    }
                    .accessibilityHidden(true)
                VStack(spacing: SpacingTokens.s) {
                    ScreenTitle(title, token: TypographyTokens.displayL)
                    Text(subtitle)
                        .typography(TypographyTokens.body)
                        .foregroundStyle(Color(ColorTokens.textSecondary))
                        .multilineTextAlignment(.center)
                }
                Pill("Coming soon", color: ColorTokens.brandFlameText)
            }
            .padding(SpacingTokens.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .arenaBackground(glow: glow, alignment: .center, offset: CGSize(width: 0, height: -40))
        }
    }
}
