import Foundation

/// Live HUD clocks (doc 07 §2, §6; migration 0020). Same as `tools/reference/pushly_ref/battle_hud.py` and Android
/// `BattleHud`; both pass `shared/test-vectors/battles/hud.json`. Times are ms since the battle start (server time).
public enum BattleHud {
    public static let roundMs: Int64 = 135_000
    public static let setMs: Int64 = 90_000
    public static let restMs: Int64 = roundMs - setMs
    public static let bo3EndMs: Int64 = 3 * roundMs - restMs
    public static let turnMs: Int64 = 5_000
    /// A Best-of-3 set ends after a pause longer than this (same gap as the result rules).
    public static let setGapMs: Int64 = 2_000

    public struct Bo3Clock: Codable, Hashable, Sendable {
        public var round: Int
        /// countdown | set | rest | over
        public var phase: String
        public var msLeft: Int64
    }

    public struct TurnState: Codable, Hashable, Sendable {
        /// anyone | me | them
        public var turn: String
        /// ms left in the current turn window (negative = overdue), nil when nobody has started
        public var msLeft: Int64?
    }

    public static func bo3Clock(_ t: Int64) -> Bo3Clock {
        if t < 0 { return Bo3Clock(round: 0, phase: "countdown", msLeft: -t) }
        if t >= bo3EndMs { return Bo3Clock(round: 2, phase: "over", msLeft: 0) }
        let round = Int(t / roundMs)
        let within = t % roundMs
        return within < setMs
            ? Bo3Clock(round: round, phase: "set", msLeft: setMs - within)
            : Bo3Clock(round: round, phase: "rest", msLeft: roundMs - within)
    }

    /// I have certainly won rounds 1 and 2: my set beat the opponent's raw count (an upper bound of their set).
    public static func bo3Clinched(mySets: [Int], theirRaw: [Int]) -> Bool {
        mySets.count >= 2 && theirRaw.count >= 2 && (0...1).allSatisfy { mySets[$0] > theirRaw[$0] }
    }

    public static func turnState(t: Int64, myLast: Int64?, theirLast: Int64?) -> TurnState {
        switch (myLast, theirLast) {
        case (nil, nil):
            return TurnState(turn: "anyone", msLeft: nil)
        case let (mine?, nil):
            return TurnState(turn: "them", msLeft: turnMs - (t - mine))
        case let (mine?, theirs?) where mine > theirs:
            return TurnState(turn: "them", msLeft: turnMs - (t - mine))
        case let (_, theirs?):
            return TurnState(turn: "me", msLeft: turnMs - (t - theirs))
        }
    }

    /// My set in each Best-of-3 round so far (continuous reps, same rule as the result).
    public static func mySets(_ reps: [BattleRules.Rep]) -> [Int] {
        (0...2).map { round in
            let inRound = reps.filter { $0.round == round }
            guard let first = inRound.map(\.t).min() else { return 0 }
            return BattleRules.continuous(inRound, gap: setGapMs, cap: first + setMs).count
        }
    }
}
