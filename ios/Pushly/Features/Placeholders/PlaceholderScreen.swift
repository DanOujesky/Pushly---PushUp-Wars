import DesignSystem
import SwiftUI

/// Temporary tab content until each feature is built (roadmap P0-08).
struct PlaceholderScreen: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        NavigationStack {
            VStack(spacing: SpacingTokens.m) {
                Text(title)
                    .font(.token(TypographyTokens.displayL))
                    .foregroundStyle(Color(ColorTokens.textPrimary))
                Text(subtitle)
                    .font(.token(TypographyTokens.body))
                    .foregroundStyle(Color(ColorTokens.textSecondary))
                    .multilineTextAlignment(.center)
            }
            .padding(SpacingTokens.gutter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(ColorTokens.bgBase))
        }
    }
}
