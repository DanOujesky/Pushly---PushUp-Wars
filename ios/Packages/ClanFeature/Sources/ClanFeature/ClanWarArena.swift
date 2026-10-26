import DesignSystem
import SwiftUI

// Live Clan War arena (D-079): a Clash-Royale-style race. Every clan runs on its own lane toward the leader's mark,
// the numbers roll up as push-ups land, "+N" pops over the clan that just scored, lanes swap places when a clan
// overtakes another and the leader wears the crown. Refreshes every 15 s while the war is live.
// Reduce Motion: no movement, the numbers just change.

/// All clans of a live war, one lane each, in standings order.
struct WarArena: View {
    let war: ClanWar
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let top = max(war.clans.map(\.score).max() ?? 0, 1)
        VStack(spacing: SpacingTokens.sm) {
            ForEach(war.clans) { s in
                WarLane(standing: s, top: top, leader: s.rank == 1 && s.score > 0)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.65, dampingFraction: 0.78), value: war.clans.map(\.score))
        .animation(reduceMotion ? nil : .spring(response: 0.65, dampingFraction: 0.78), value: war.clans.map(\.id))
    }
}

/// One clan's lane: name, the track with the running emblem, the rolling score.
struct WarLane: View {
    let standing: ClanWar.Standing
    let top: Int
    let leader: Bool
    @State private var gain: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var color: Color { Color(badgeColor(standing.clan)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: SpacingTokens.xs) {
                Text(verbatim: rankMedal(standing.rank)).font(.callout)
                Text(verbatim: standing.clan.name)
                    .typography(TypographyTokens.labelDisplay)
                    .foregroundStyle(Color(standing.isMine ? ColorTokens.brandFlameText : ColorTokens.textSecondary))
                    .lineLimit(1)
                if standing.isMine {
                    Text("YOU").typography(TypographyTokens.overline).foregroundStyle(Color(ColorTokens.brandFlameText))
                }
                Spacer(minLength: SpacingTokens.xs)
                Text(verbatim: "\(standing.score)")
                    .typography(TypographyTokens.titleM)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(standing.score)))
                    .foregroundStyle(Color(leader ? ColorTokens.leagueGold : ColorTokens.textPrimary))
            }
            GeometryReader { geo in
                let marker: CGFloat = 34
                let x = (geo.size.width - marker) * CGFloat(standing.score) / CGFloat(top)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.06)).frame(height: 12)
                    Capsule()
                        .fill(LinearGradient(colors: [color.opacity(0.15), color.opacity(0.9)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(12, x + marker / 2), height: 12)
                        .shadow(color: color.opacity(0.6), radius: leader ? 8 : 0)
                    ClanEmblemView(style: standing.clan.badge, tag: standing.clan.tag, size: marker)
                        .overlay(alignment: .top) {
                            if leader { Text(verbatim: "👑").font(.system(size: 14)).offset(y: -13).accessibilityHidden(true) }
                        }
                        .offset(x: x)
                    if let gain {
                        Text(verbatim: "+\(gain)")
                            .typography(TypographyTokens.titleS)
                            .foregroundStyle(Color(ColorTokens.stateSuccessText))
                            .shadow(color: .black.opacity(0.6), radius: 2)
                            .offset(x: min(x + marker + 4, geo.size.width - 44))
                            .transition(.asymmetric(insertion: .scale(scale: 0.4).combined(with: .opacity), removal: .opacity))
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 38)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(standing.clan.name), place \(standing.rank ?? 0), \(standing.score) points"))
        .onChange(of: standing.score) { old, new in
            guard new > old, !reduceMotion else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { gain = new - old }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.2))
                withAnimation(.easeOut(duration: 0.4)) { gain = nil }
            }
        }
    }
}

/// The newest feed line, sliding in when someone scores.
struct WarTicker: View {
    let feed: [ClanWar.FeedItem]

    var body: some View {
        if let f = feed.first {
            HStack(spacing: SpacingTokens.xs) {
                Text(verbatim: f.mine ? "🔥" : "⚔️").accessibilityHidden(true)
                Text(verbatim: f.username).typography(TypographyTokens.bodyS).foregroundStyle(Color(ColorTokens.textPrimary)).lineLimit(1)
                Text(verbatim: "+\(f.points)").typography(TypographyTokens.titleS)
                    .foregroundStyle(Color(f.mine ? ColorTokens.stateSuccessText : ColorTokens.stateDanger))
                Text("for \(f.clanName)").typography(TypographyTokens.caption).foregroundStyle(Color(ColorTokens.textTertiary)).lineLimit(1)
                Spacer(minLength: 0)
                Text(verbatim: WarTicker.ago(f.at)).typography(TypographyTokens.caption).foregroundStyle(Color(ColorTokens.textTertiary))
            }
            .id(f.at + f.username)
            .transition(.push(from: .bottom))
            .padding(.horizontal, SpacingTokens.sm)
            .padding(.vertical, SpacingTokens.xs)
            .background(Color.black.opacity(0.3), in: Capsule())
            .accessibilityElement(children: .combine)
        }
    }

    static func ago(_ iso: String, now: Date = Date()) -> String {
        let trimmed = iso.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        guard let d = ISO8601DateFormatter().date(from: trimmed) else { return "" }
        let m = Int(now.timeIntervalSince(d) / 60)
        if m < 1 { return String(localized: "now") }
        if m < 60 { return String(localized: "\(m) min") }
        let h = m / 60
        return h < 24 ? String(localized: "\(h) h") : String(localized: "\(h / 24) d")
    }
}
