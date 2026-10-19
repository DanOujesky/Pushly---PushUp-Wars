import DesignSystem
import SwiftUI

/// Three short value screens (doc 02 PS-01), swipeable and skippable.
public struct WelcomeView: View {
    let onContinue: () -> Void
    @State private var page = 0

    private struct Page: Identifiable {
        let id: Int
        let title: LocalizedStringKey
        let text: LocalizedStringKey
        let glow: TokenColor
    }

    private let pages: [Page] = [
        Page(id: 0, title: "Your alarm.\nYour push-ups.",
             text: "It only stops when the camera sees real push-ups. No snoozing your way out.", glow: ColorTokens.brandFlame),
        Page(id: 1, title: "Battle anyone.\nLive.",
             text: "Split-screen push-up duels with friends or players worldwide. Win trophies, climb leagues.",
             glow: ColorTokens.brandVolt),
        Page(id: 2, title: "Climb with\nyour clan.",
             text: "Every push-up counts for your clan in the weekly Clan War.", glow: ColorTokens.brandCyan),
    ]

    public init(onContinue: @escaping () -> Void) {
        self.onContinue = onContinue
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Wordmark()
                Spacer()
                GhostButton("Skip", action: onContinue)
            }
            .padding(.horizontal, SpacingTokens.l)

            TabView(selection: $page) {
                ForEach(pages) { p in
                    ScrollView {
                        VStack(alignment: .leading, spacing: SpacingTokens.xl - 4) {
                            hero(for: p)
                            VStack(alignment: .leading, spacing: SpacingTokens.sm) {
                                ScreenTitle(p.title)
                                Text(p.text)
                                    .typography(TypographyTokens.body)
                                    .foregroundStyle(Color(ColorTokens.textSecondary))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.horizontal, SpacingTokens.l)
                        .padding(.top, SpacingTokens.l)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .tag(p.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack(spacing: SpacingTokens.l) {
                PageDots(count: pages.count, index: page)
                PrimaryButton(page == pages.count - 1 ? "Get started" : "Next") {
                    if page < pages.count - 1 {
                        withAnimation(.easeInOut(duration: MotionTokens.baseSeconds)) { page += 1 }
                    } else {
                        onContinue()
                    }
                }
            }
            .padding(.horizontal, SpacingTokens.l)
            .padding(.bottom, SpacingTokens.m)
        }
        .padding(.top, SpacingTokens.s)
        .background(Color(ColorTokens.bgBase).ignoresSafeArea())
    }

    private func hero(for page: Page) -> some View {
        ZStack {
            GlowSpot(page.glow, size: 380, intensity: 0.32)
            switch page.id {
            case 0: AlarmHero()
            case 1: BattleHero()
            default: ClanHero()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
        .background(Color(ColorTokens.bgSurface))
        .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: RadiusTokens.xl, style: .continuous).stroke(Color(ColorTokens.strokeSubtle), lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// Illustration: the wake challenge counter mid-way.
private struct AlarmHero: View {
    var body: some View {
        VStack(spacing: SpacingTokens.xs) {
            Label("06:30 · Alarm ringing", systemImage: "alarm.fill")
            .typography(TypographyTokens.overline)
            .foregroundStyle(Color(ColorTokens.brandFlameText))
            .padding(.horizontal, SpacingTokens.sm)
            .padding(.vertical, SpacingTokens.xs + 2)
            .background(Color(ColorTokens.brandFlame).opacity(0.14), in: Capsule())
            Text(verbatim: "14")
                .font(.token(TypographyTokens.displayCounter, fixedSize: 140))
                .foregroundStyle(Color(ColorTokens.textPrimary))
                .padding(.vertical, -SpacingTokens.m)
            Text("of 20 push-ups")
                .typography(TypographyTokens.labelDisplay)
                .foregroundStyle(Color(ColorTokens.textTertiary))
            GradientProgressBar(value: 0.7)
                .frame(width: 220)
                .padding(.top, SpacingTokens.sm)
        }
    }
}

/// Illustration: a live 1v1 battle score.
private struct BattleHero: View {
    var body: some View {
        VStack(spacing: SpacingTokens.m) {
            Pill("Live battle", color: ColorTokens.brandVoltText)
            HStack(alignment: .center, spacing: SpacingTokens.m) {
                fighter(name: "You", initial: "Y", score: "18", preset: "preset.flame")
                Text(verbatim: "VS")
                    .font(.token(TypographyTokens.displayWordmark, fixedSize: 28))
                    .foregroundStyle(Color(ColorTokens.textTertiary))
                fighter(name: "Alex", initial: "A", score: "15", preset: "preset.volt")
            }
        }
    }

    private func fighter(name: LocalizedStringKey, initial: String, score: String, preset: String) -> some View {
        VStack(spacing: SpacingTokens.s) {
            AvatarView(username: initial, presetID: preset, size: 64)
            Text(verbatim: score)
                .font(.token(TypographyTokens.stat, fixedSize: 64))
                .foregroundStyle(Color(ColorTokens.textPrimary))
            Text(name)
                .typography(TypographyTokens.overline)
                .foregroundStyle(Color(ColorTokens.textSecondary))
        }
        .frame(width: 100)
    }
}

/// Illustration: this week's Clan War totals.
private struct ClanHero: View {
    var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.m) {
            Text("Clan War · Week 42")
                .typography(TypographyTokens.overline)
                .foregroundStyle(Color(ColorTokens.brandCyan))
            row(name: "Iron Wolves", total: "4,210", share: 1.0, highlight: true)
            row(name: "Night Owls", total: "3,980", share: 0.94, highlight: false)
        }
        .padding(SpacingTokens.l)
    }

    private func row(name: LocalizedStringKey, total: String, share: Double, highlight: Bool) -> some View {
        VStack(alignment: .leading, spacing: SpacingTokens.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(name)
                    .typography(TypographyTokens.titleS)
                    .foregroundStyle(Color(highlight ? ColorTokens.textPrimary : ColorTokens.textSecondary))
                Spacer()
                Text(verbatim: total)
                    .font(.token(TypographyTokens.stat, fixedSize: 36))
                    .foregroundStyle(Color(highlight ? ColorTokens.textPrimary : ColorTokens.textSecondary))
            }
            GradientProgressBar(value: share, height: 10)
                .opacity(highlight ? 1 : 0.45)
        }
    }
}

#Preview { WelcomeView {}.preferredColorScheme(.dark) }
