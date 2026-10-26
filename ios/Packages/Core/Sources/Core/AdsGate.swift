import Foundation

/// When an ad may be shown (doc 13 §1, CLAUDE.md §4.5). Every ad call goes through `AdsGate.canShow`; the first failing
/// rule is the reason. Same rules as Android `AdsGate` and the reference `tools/reference/pushly_ref/ads.py`
/// (vectors `shared/test-vectors/ads/gate.json`). "Day" caps are rolling 24 h windows.
public enum AdsGate {
    public enum Kind: Sendable { case interstitial, banner, rewarded }

    public static let placements: [String: Kind] = [
        "battle_results_interstitial": .interstitial,
        "ranks_banner": .banner,
        "stats_banner": .banner,
        "clan_banner": .banner,
        "rewarded_streak_freeze": .rewarded,
        "rewarded_extra_ghost": .rewarded,
    ]

    public struct Shown: Codable, Hashable, Sendable {
        public var placement: String
        public var atMs: Int64
        public init(placement: String, atMs: Int64) {
            self.placement = placement
            self.atMs = atMs
        }
    }

    public struct Context: Codable, Hashable, Sendable {
        public var isPro = false
        public var wakeActive = false
        public var lastWakeEndedMs: Int64?
        public var cameraActive = false
        /// none | matchmaking | lobby | live | results
        public var battlePhase = "none"
        /// other | onboarding | alarm_editor | alarm_health | wake | camera | battle
        public var screen = "other"
        public var completedSessions = 0
        public var nowMs: Int64 = 0
        public var lastTapMs: Int64?
        public var shown: [Shown] = []
        public var battlesSinceInterstitial = 0
        public var freezesAvailable = 0

        public init() {}
    }

    static let day: Int64 = 24 * 3600 * 1000
    static let forbiddenScreens: Set<String> = ["onboarding", "alarm_editor", "alarm_health", "wake", "camera", "battle"]
    static let busyBattle: Set<String> = ["matchmaking", "lobby", "live", "results"]

    private static func count(_ shown: [Shown], now: Int64, window: Int64, _ placements: Set<String>) -> Int {
        shown.filter { placements.contains($0.placement) && now - $0.atMs < window }.count
    }

    /// (allowed, reason) — reason is "ok" when allowed.
    public static func canShow(_ placement: String, _ ctx: Context) -> (allowed: Bool, reason: String) {
        guard let kind = placements[placement] else { return (false, "unknown_placement") }
        let now = ctx.nowMs
        if ctx.isPro { return (false, "pro") }
        if ctx.wakeActive { return (false, "wake_active") }
        if let last = ctx.lastWakeEndedMs, now - last < 10 * 60 * 1000 { return (false, "wake_cooldown") }
        if ctx.cameraActive { return (false, "camera_active") }
        if busyBattle.contains(ctx.battlePhase) { return (false, "battle_active") }
        if forbiddenScreens.contains(ctx.screen) { return (false, "forbidden_screen") }
        if ctx.completedSessions < 2 { return (false, "new_user") }
        if kind != .banner {
            let nonBanner = Set(placements.filter { $0.value != .banner }.keys)
            if count(ctx.shown, now: now, window: day, nonBanner) >= 8 { return (false, "global_cap") }
        }
        // D-082: interstitials only for players with 5+ sessions, every 2 battles AND 15 min, max 4 a day
        if kind == .interstitial, ctx.completedSessions < 5 { return (false, "new_user") }
        if kind == .interstitial, let tap = ctx.lastTapMs, now - tap < 2000 { return (false, "tap_guard") }
        switch placement {
        case "battle_results_interstitial":
            if ctx.battlesSinceInterstitial < 2 { return (false, "battle_frequency") }
            if let last = ctx.shown.filter({ $0.placement == placement }).map(\.atMs).max(), now - last < 15 * 60 * 1000 {
                return (false, "min_gap")
            }
            if count(ctx.shown, now: now, window: day, [placement]) >= 4 { return (false, "daily_cap") }
        case "rewarded_streak_freeze":
            if ctx.freezesAvailable > 0 { return (false, "has_freeze") }
            if count(ctx.shown, now: now, window: 7 * day, [placement]) >= 1 { return (false, "weekly_cap") }
        case "rewarded_extra_ghost":
            if count(ctx.shown, now: now, window: day, [placement]) >= 3 { return (false, "daily_cap") }
        default:
            break
        }
        return (true, "ok")
    }
}
