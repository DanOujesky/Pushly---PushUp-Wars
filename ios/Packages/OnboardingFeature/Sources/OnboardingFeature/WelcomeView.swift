import DesignSystem
import SwiftUI

/// Three short value screens (doc 02 PS-01), swipeable and skippable.
public struct WelcomeView: View {
    let onContinue: () -> Void
    @State private var page = 0

    private struct Page: Identifiable {
        let id: Int
        let symbol: String
        let title: LocalizedStringKey
        let text: LocalizedStringKey
        let color: TokenColor
    }

    private let pages: [Page] = [
        Page(id: 0, symbol: "alarm.waves.left.and.right.fill", title: "Your alarm. Your push-ups.",
             text: "The alarm only stops when the camera sees your push-ups.", color: ColorTokens.brandFlame),
        Page(id: 1, symbol: "figure.strengthtraining.traditional", title: "Battle anyone, live.",
             text: "Split-screen push-up duels with friends or players worldwide.", color: ColorTokens.brandVolt),
        Page(id: 2, symbol: "shield.lefthalf.filled", title: "Climb with your clan.",
             text: "Every push-up counts for your clan in the weekly Clan War.", color: ColorTokens.brandLime),
    ]

    public init(onContinue: @escaping () -> Void) {
        self.onContinue = onContinue
    }

    public var body: some View {
        VStack(spacing: SpacingTokens.l) {
            HStack {
                Spacer()
                Button("Skip", action: onContinue)
                    .font(.token(TypographyTokens.bodyS))
                    .foregroundStyle(Color(ColorTokens.textSecondary))
                    .frame(minWidth: TouchTarget.minimum, minHeight: TouchTarget.minimum)
            }
            TabView(selection: $page) {
                ForEach(pages) { p in
                    VStack(spacing: SpacingTokens.l) {
                        Image(systemName: p.symbol)
                            .font(.system(size: 96, weight: .bold))
                            .foregroundStyle(Color(p.color))
                            .accessibilityHidden(true)
                        Text(p.title)
                            .font(.token(TypographyTokens.displayL))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color(ColorTokens.textPrimary))
                        Text(p.text)
                            .font(.token(TypographyTokens.body))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color(ColorTokens.textSecondary))
                    }
                    .padding(.horizontal, SpacingTokens.l)
                    .tag(p.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            PrimaryButton(page == pages.count - 1 ? "Get started" : "Next") {
                if page < pages.count - 1 {
                    withAnimation(.easeInOut(duration: MotionTokens.baseSeconds)) { page += 1 }
                } else {
                    onContinue()
                }
            }
        }
        .padding(SpacingTokens.gutter)
        .background(Color(ColorTokens.bgBase))
    }
}

#Preview { WelcomeView {} }
