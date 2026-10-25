import Core
import DesignSystem
import SwiftUI

/// Pushly Pro paywall (doc 13 §2, D-073, D-074). Opened only from explicit entry points (Profile, "Remove ads", the
/// ghost limit, a locked Pro sound / frame / emblem) — never after a wake flow or a lost battle. Honest copy: comfort
/// and cosmetics only, never pay-to-win.
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
                hero
                perkGrid
                FreeVsPro()
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
                Text("Never pay-to-win: trophies, ranks and Clan Wars are won with push-ups only.")
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.textTertiary))
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                footer
            }
            .padding(SpacingTokens.l)
        }
        .arenaBackground(glow: ColorTokens.leagueGold, alignment: .top, offset: CGSize(width: 0, height: -220))
        .task { await shop.loadPlans() }
    }

    /// You, with a gold frame and the PRO badge — what Pro looks like on you.
    private var hero: some View {
        VStack(spacing: SpacingTokens.sm) {
            ZStack(alignment: .bottomTrailing) {
                AvatarView(username: shop.me?.username ?? "P", presetID: shop.me?.avatarPreset, size: 112,
                           frame: shop.isPro ? (ProState.shared.frame ?? "gold") : "gold")
                ProBadge(size: .large).offset(x: 10, y: 6)
            }
            .padding(.top, SpacingTokens.s)
            Text("Pushly Pro")
                .typography(TypographyTokens.displayL)
                .foregroundStyle(Color(ColorTokens.textPrimary))
            Text(reasonLine)
                .typography(TypographyTokens.body)
                .foregroundStyle(Color(ColorTokens.textSecondary))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var reasonLine: LocalizedStringKey {
        switch shop.paywallReason {
        case "sound": "Wake up to the Pro sound pack — and get everything else in Pro."
        case "frame": "Stand out everywhere with a Pro frame around your avatar."
        case "emblem": "Give your clan a legendary emblem."
        case "ghost_limit": "Race ghosts as often as you like."
        case "remove_ads": "No ads. Anywhere. Ever."
        default: "No ads, legendary looks and comfort extras — and you keep Pushly growing."
        }
    }

    private var perkGrid: some View {
        let perks = ProPerk.ordered(for: shop.paywallReason)
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: SpacingTokens.sm), GridItem(.flexible())], spacing: SpacingTokens.sm) {
            ForEach(perks) { perk in
                VStack(alignment: .leading, spacing: SpacingTokens.xs) {
                    Text(verbatim: perk.glyph).font(.system(size: 28)).accessibilityHidden(true)
                    Text(perk.title).typography(TypographyTokens.titleS)
                        .foregroundStyle(Color(ColorTokens.textPrimary))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(perk.detail).typography(TypographyTokens.caption)
                        .foregroundStyle(Color(ColorTokens.textSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(SpacingTokens.sm)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(ColorTokens.bgSurface).opacity(0.9), in: RoundedRectangle(cornerRadius: RadiusTokens.m))
                .overlay(RoundedRectangle(cornerRadius: RadiusTokens.m)
                    .strokeBorder(Color(perk.highlight(for: shop.paywallReason) ? ColorTokens.leagueGold : ColorTokens.strokeSubtle),
                                  lineWidth: perk.highlight(for: shop.paywallReason) ? 2 : 1))
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var plans: some View {
        VStack(spacing: SpacingTokens.sm) {
            ForEach(shop.plans) { p in
                Button { selected = p.id } label: { PlanCard(plan: p, selected: plan?.id == p.id, monthly: monthlyPrice) }
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

    private var monthlyPrice: PaywallPlan? { shop.plans.first { $0.kind == .monthly } }

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

/// What you get, side by side (only things that exist — D-074).
struct FreeVsPro: View {
    private struct Row: Identifiable {
        let id: Int
        let title: LocalizedStringKey
        let free: LocalizedStringKey
        let pro: LocalizedStringKey
    }

    private let rows: [Row] = [
        Row(id: 0, title: "Ads", free: "Some", pro: "None"),
        Row(id: 1, title: "Ghost battles", free: "3 a day", pro: "Unlimited"),
        Row(id: 2, title: "Streak freezes", free: "Earn them", pro: "+2 every month"),
        Row(id: 3, title: "Profile frames", free: "—", pro: "5"),
        Row(id: 4, title: "Alarm sounds", free: "4", pro: "8"),
        Row(id: 5, title: "Clan emblems", free: "8", pro: "16"),
        Row(id: 6, title: "Trophies & ranks", free: "Push-ups only", pro: "Push-ups only"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("").frame(maxWidth: .infinity, alignment: .leading)
                Text("Free").typography(TypographyTokens.labelDisplay).foregroundStyle(Color(ColorTokens.textSecondary))
                    .frame(width: 96)
                ProBadge().frame(width: 96)
            }
            .padding(.vertical, SpacingTokens.xs)
            ForEach(rows) { r in
                HStack {
                    Text(r.title).typography(TypographyTokens.bodyS).foregroundStyle(Color(ColorTokens.textPrimary))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(r.free).typography(TypographyTokens.caption).foregroundStyle(Color(ColorTokens.textTertiary))
                        .frame(width: 96).multilineTextAlignment(.center)
                    Text(r.pro).typography(TypographyTokens.caption).foregroundStyle(Color(ColorTokens.leagueGold))
                        .frame(width: 96).multilineTextAlignment(.center)
                }
                .padding(.vertical, SpacingTokens.xs + 2)
                .overlay(alignment: .top) { Rectangle().fill(Color(ColorTokens.strokeSubtle)).frame(height: 1) }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, SpacingTokens.m)
        .padding(.vertical, SpacingTokens.s)
        .background(Color(ColorTokens.bgSurface).opacity(0.9), in: RoundedRectangle(cornerRadius: RadiusTokens.m))
    }
}

struct PlanCard: View {
    let plan: PaywallPlan
    let selected: Bool
    var monthly: PaywallPlan?

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

/// What Pro gives — only things that exist (D-073, D-074). Same list on Android.
struct ProPerk: Identifiable {
    let id: String
    let glyph: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    static var all: [ProPerk] {
        [
            ProPerk(id: "ads", glyph: "🚫", title: "No ads", detail: "Not a single banner or video, anywhere."),
            ProPerk(id: "frame", glyph: "🖼️", title: "5 Pro frames", detail: "Gold, Neon, Fire, Ice, Royal — everyone sees them."),
            ProPerk(id: "sound", glyph: "🎺", title: "Pro sound pack", detail: "Thunder, Anthem, Drill and Sunrise alarms."),
            ProPerk(id: "emblem", glyph: "🐉", title: "8 Pro clan emblems", detail: "Dragon, Crown, Diamond and more for your clan."),
            ProPerk(id: "ghost", glyph: "👻", title: "Unlimited ghosts", detail: "Free: 3 a day. Ghosts never change trophies."),
            ProPerk(id: "freeze", glyph: "❄️", title: "2 freezes a month", detail: "Your streak survives a sick day."),
            ProPerk(id: "badge", glyph: "👑", title: "PRO badge", detail: "Next to your name in ranks, clans and friends."),
            ProPerk(id: "support", glyph: "❤️", title: "Support an indie dev", detail: "Pushly is built by one student."),
        ]
    }

    /// The perk behind the paywall reason comes first.
    static func ordered(for reason: String?) -> [ProPerk] {
        let key = focus(reason)
        return all.filter { $0.id == key } + all.filter { $0.id != key }
    }

    static func focus(_ reason: String?) -> String? {
        switch reason {
        case "sound": "sound"
        case "frame": "frame"
        case "emblem": "emblem"
        case "ghost_limit": "ghost"
        case "remove_ads": "ads"
        default: nil
        }
    }

    func highlight(for reason: String?) -> Bool { ProPerk.focus(reason) == id }
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
                    Text(shop.isPro ? "Thank you for supporting Pushly!" : "No ads, Pro frames, sound pack, clan emblems and more")
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

/// Profile → "Profile frame": pick a Pro frame (D-074). Free users see them and get the paywall on tap.
public struct ProFramePicker: View {
    let shop: Shop

    public init(shop: Shop) { self.shop = shop }

    public var body: some View {
        VStack(alignment: .leading, spacing: SpacingTokens.s) {
            HStack(spacing: SpacingTokens.xs) {
                Text("Profile frame").typography(TypographyTokens.titleS).foregroundStyle(Color(ColorTokens.textPrimary))
                ProBadge()
            }
            ScrollView(.horizontal) {
                HStack(spacing: SpacingTokens.sm) {
                    option(nil)
                    ForEach(Cosmetics.frames, id: \.self) { option($0) }
                }
                .padding(.vertical, SpacingTokens.xs)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func option(_ id: String?) -> some View {
        let current = shop.isPro ? ProState.shared.frame : nil
        let selected = current == id
        return Button {
            if id != nil, !shop.isPro {
                Monetization.showPaywall("frame")
            } else {
                Task { await shop.setFrame(id) }
            }
        } label: {
            VStack(spacing: SpacingTokens.xs) {
                AvatarView(username: shop.me?.username ?? "P", presetID: shop.me?.avatarPreset, size: 56, frame: id)
                    .opacity(id != nil && !shop.isPro ? 0.6 : 1)
                Text(Self.name(id)).typography(TypographyTokens.caption)
                    .foregroundStyle(Color(selected ? ColorTokens.leagueGold : ColorTokens.textSecondary))
            }
            .padding(SpacingTokens.xs)
            .background(RoundedRectangle(cornerRadius: RadiusTokens.m)
                .strokeBorder(selected ? Color(ColorTokens.leagueGold) : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .disabled(shop.busy)
        .accessibilityLabel(Text(Self.name(id)))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    static func name(_ id: String?) -> LocalizedStringKey {
        switch id {
        case "gold": "Gold"
        case "neon": "Neon"
        case "fire": "Fire"
        case "ice": "Ice"
        case "royal": "Royal"
        default: "None"
        }
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
