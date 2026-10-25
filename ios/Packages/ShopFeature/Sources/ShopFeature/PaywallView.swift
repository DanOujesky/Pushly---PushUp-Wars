import Core
import DesignSystem
import SwiftUI

/// Pushly Pro paywall (doc 13 §2, D-073). Opened only from explicit entry points (Profile, "Remove ads", the ghost
/// limit) — never after a wake flow or a lost battle. Honest copy: comfort and cosmetics only, never pay-to-win.
public struct PaywallView: View {
    let shop: Shop
    let onClose: () -> Void
    @State private var selected: String?
    @Environment(\.openURL) private var openURL

    public init(shop: Shop, onClose: @escaping () -> Void) {
        self.shop = shop
        self.onClose = onClose
    }

    private var plan: PaywallPlan? {
        shop.plans.first { $0.id == selected } ?? shop.plans.first
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpacingTokens.l) {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color(ColorTokens.textSecondary))
                            .frame(width: TouchTarget.minimum, height: TouchTarget.minimum)
                    }
                    .accessibilityLabel(Text("Close"))
                }
                VStack(alignment: .leading, spacing: SpacingTokens.s) {
                    ProBadge(size: .large)
                    Text("Pushly Pro")
                        .typography(TypographyTokens.displayL)
                        .foregroundStyle(Color(ColorTokens.textPrimary))
                    Text("Support Pushly and get the comfort extras. Never pay-to-win — trophies are earned with push-ups only.")
                        .typography(TypographyTokens.body)
                        .foregroundStyle(Color(ColorTokens.textSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: SpacingTokens.sm) {
                    ForEach(ProPerk.all) { perk in
                        HStack(alignment: .top, spacing: SpacingTokens.sm) {
                            Image(systemName: perk.symbol)
                                .font(.title3)
                                .foregroundStyle(Color(ColorTokens.leagueGold))
                                .frame(width: 32)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(perk.title).typography(TypographyTokens.titleS)
                                    .foregroundStyle(Color(ColorTokens.textPrimary))
                                Text(perk.detail).typography(TypographyTokens.caption)
                                    .foregroundStyle(Color(ColorTokens.textSecondary))
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                if shop.isPro {
                    InlineBanner("You have Pushly Pro — thank you! Manage or cancel it in your App Store subscriptions.", kind: .success)
                } else if !shop.purchasesAvailable {
                    InlineBanner("Pushly Pro is coming very soon. Thanks for wanting to support Pushly!", kind: .info)
                } else if shop.loadingPlans && shop.plans.isEmpty {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    plans
                }
                if let message = shop.message {
                    InlineBanner(LocalizedStringKey(message), kind: .info)
                }
                footer
            }
            .padding(SpacingTokens.l)
        }
        .arenaBackground(glow: ColorTokens.leagueGold, alignment: .top, offset: CGSize(width: 0, height: -220))
        .task { await shop.loadPlans() }
    }

    private var plans: some View {
        VStack(spacing: SpacingTokens.sm) {
            ForEach(shop.plans) { p in
                Button { selected = p.id } label: { PlanCard(plan: p, selected: plan?.id == p.id) }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(plan?.id == p.id ? .isSelected : [])
            }
            if let plan {
                PrimaryButton(plan.trialDays != nil ? "Start free trial" : "Get Pushly Pro", isLoading: shop.busy) {
                    Task { if await shop.purchase(plan) { onClose() } }
                }
                Text(Self.terms(plan))
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.textTertiary))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: SpacingTokens.m) {
            if shop.purchasesAvailable {
                Button("Restore purchases") { Task { await shop.restore() } }
            }
            Spacer()
            Button("Terms") { openURL(LegalLinks.terms) }
            Button("Privacy") { openURL(LegalLinks.privacy) }
        }
        .typography(TypographyTokens.caption)
        .foregroundStyle(Color(ColorTokens.textSecondary))
        .frame(minHeight: TouchTarget.minimum)
    }

    /// Store-required renewal terms under the button.
    static func terms(_ plan: PaywallPlan) -> String {
        switch plan.kind {
        case .lifetime:
            return String(localized: "One-time purchase of \(plan.price). No subscription.")
        case .monthly, .annual, .other:
            let period = plan.kind == .monthly ? String(localized: "month") : String(localized: "year")
            if let days = plan.trialDays {
                return String(localized: "\(days) days free, then \(plan.price) per \(period). Renews automatically until you cancel — at least 24 hours before the period ends, in your App Store settings.")
            }
            return String(localized: "\(plan.price) per \(period). Renews automatically until you cancel — at least 24 hours before the period ends, in your App Store settings.")
        }
    }
}

struct PlanCard: View {
    let plan: PaywallPlan
    let selected: Bool

    var body: some View {
        HStack(spacing: SpacingTokens.sm) {
            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(Color(selected ? ColorTokens.leagueGold : ColorTokens.textTertiary))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(PlanCard.title(plan.kind)).typography(TypographyTokens.titleS)
                    .foregroundStyle(Color(ColorTokens.textPrimary))
                if let days = plan.trialDays {
                    Text("\(days)-day free trial").typography(TypographyTokens.caption)
                        .foregroundStyle(Color(ColorTokens.stateSuccessText))
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: plan.price).typography(TypographyTokens.titleS)
                    .foregroundStyle(Color(ColorTokens.textPrimary))
                if plan.kind == .annual {
                    Text("Best value").typography(TypographyTokens.caption)
                        .foregroundStyle(Color(ColorTokens.leagueGold))
                }
            }
        }
        .padding(SpacingTokens.m)
        .frame(minHeight: TouchTarget.minimum)
        .background(Color(ColorTokens.bgSurface), in: RoundedRectangle(cornerRadius: RadiusTokens.m))
        .overlay(RoundedRectangle(cornerRadius: RadiusTokens.m)
            .strokeBorder(Color(selected ? ColorTokens.leagueGold : ColorTokens.strokeSubtle), lineWidth: selected ? 2 : 1))
        .accessibilityElement(children: .combine)
    }

    static func title(_ kind: PaywallPlan.Kind) -> LocalizedStringKey {
        switch kind {
        case .monthly: "Monthly"
        case .annual: "Yearly"
        case .lifetime: "Lifetime"
        case .other: "Pushly Pro"
        }
    }
}

/// What Pro gives — only things that exist (D-073). Same list on Android.
struct ProPerk: Identifiable {
    let id: Int
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    static let all: [ProPerk] = [
        ProPerk(id: 0, symbol: "nosign", title: "No ads", detail: "Not a single banner or video, anywhere in the app."),
        ProPerk(id: 1, symbol: "figure.run", title: "Unlimited ghost battles",
                detail: "Free players get 3 a day. Ghosts never change trophies."),
        ProPerk(id: 2, symbol: "snowflake", title: "2 streak freezes every month",
                detail: "Your wake streak survives a sick day or a trip."),
        ProPerk(id: 3, symbol: "crown.fill", title: "PRO badge", detail: "Next to your name in leaderboards, clans and friend lists."),
        ProPerk(id: 4, symbol: "heart.fill", title: "Support a student indie developer",
                detail: "Pushly is built by one person. Pro keeps it growing — and ad-free for you."),
    ]
}

/// Profile → "Pushly Pro" row: status for Pro users, the entry point for everyone else.
public struct ProProfileRow: View {
    let shop: Shop

    public init(shop: Shop) { self.shop = shop }

    public var body: some View {
        Button { Monetization.showPaywall("profile") } label: {
            HStack(spacing: SpacingTokens.sm) {
                ProBadge(size: .regular)
                VStack(alignment: .leading, spacing: 2) {
                    Text(shop.isPro ? "You have Pushly Pro" : "Get Pushly Pro")
                        .typography(TypographyTokens.titleS)
                        .foregroundStyle(Color(ColorTokens.textPrimary))
                    Text(shop.isPro ? "Thank you for supporting Pushly!" : "No ads, unlimited ghosts, monthly streak freezes")
                        .typography(TypographyTokens.caption)
                        .foregroundStyle(Color(ColorTokens.textSecondary))
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Color(ColorTokens.textTertiary)).accessibilityHidden(true)
            }
            .frame(minHeight: TouchTarget.minimum)
        }
        .buttonStyle(.plain)
    }
}

/// "Ad privacy settings" (UMP) — only shown where the law needs an entry point (EU).
public struct AdPrivacyRow: View {
    let shop: Shop

    public init(shop: Shop) { self.shop = shop }

    public var body: some View {
        if shop.ads.privacyOptionsRequired {
            Button { Task { await shop.ads.showPrivacyOptions() } } label: {
                Label("Ad privacy settings", systemImage: "hand.raised.fill")
                    .frame(minHeight: TouchTarget.minimum)
            }
        }
    }
}
