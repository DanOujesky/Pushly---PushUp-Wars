import Foundation

/// How a finished battle went, for History (D-077): the final score from my side, by how much it was won or lost and
/// whether it was a close call. Same rules as Android `BattleRecap`; both are tested with the same cases.
public struct BattleRecap: Hashable, Sendable {
    public enum Outcome: String, Sendable { case win, loss, draw }

    /// What decided it.
    public enum Margin: Hashable, Sendable {
        /// Difference in push-ups (max reps, endurance, turns, speed when only one finished).
        case reps(Int)
        /// Speed: difference in finish time, ms.
        case time(Int64)
        /// Best of 3: rounds won by me and by them.
        case rounds(Int, Int)
        /// Same reps; better average form won.
        case form
        /// Somebody left; `byMe` = I left.
        case forfeit(byMe: Bool)
        /// Turns: somebody missed their 5 s window.
        case turnMissed(byMe: Bool)
        case draw
        /// Battle voided (no valid result).
        case void
    }

    public var outcome: Outcome
    public var mine: Int
    public var theirs: Int
    public var margin: Margin

    /// A nail-biter: decided by one push-up, under a second, 2–1 in rounds, on form, or a draw.
    public var isClose: Bool {
        switch margin {
        case .reps(let n): n <= 1
        case .time(let ms): ms <= 1000
        case .rounds(let a, let b): abs(a - b) == 1
        case .form, .draw: true
        case .forfeit, .turnMissed, .void: false
        }
    }

    public init(outcome: Outcome, mine: Int, theirs: Int, margin: Margin) {
        self.outcome = outcome
        self.mine = mine
        self.theirs = theirs
        self.margin = margin
    }

    public init(_ battle: Battle) {
        let meA = battle.me == "a"
        outcome = battle.winner == "me" ? .win : battle.winner == "opponent" ? .loss : .draw
        guard let r = battle.result else {
            mine = battle.myScore
            theirs = battle.theirScore
            margin = battle.status == "void" ? .void : .draw
            return
        }
        let me = meA ? r.a : r.b
        let them = meA ? r.b : r.a
        mine = me.reps
        theirs = them.reps
        let iLost = outcome == .loss
        switch r.reason {
        case "forfeit":
            margin = .forfeit(byMe: iLost)
        case "turn_missed":
            margin = .turnMissed(byMe: iLost)
        case "draw":
            margin = .draw
        case "quality":
            margin = .form
        case "rounds":
            margin = .rounds(me.rounds ?? 0, them.rounds ?? 0)
        case "target":
            if let a = me.finishT, let b = them.finishT {
                margin = .time(abs(a - b))
            } else {
                margin = .reps(abs(me.reps - them.reps))
            }
        default:
            margin = outcome == .draw ? .draw : .reps(abs(me.reps - them.reps))
        }
    }

    /// "Lost by 1 push-up", "Won by 0.4 s", "Won 2–1 in rounds", "Opponent left" …
    public var line: String {
        let won = outcome == .win
        switch margin {
        case .reps(let n):
            if n == 1 { return won ? String(localized: "Won by 1 push-up") : String(localized: "Lost by 1 push-up") }
            return won ? String(localized: "Won by \(n) push-ups") : String(localized: "Lost by \(n) push-ups")
        case .time(let ms):
            let s = (Double(ms) / 1000).formatted(.number.precision(.fractionLength(1)))
            return won ? String(localized: "Won by \(s) s") : String(localized: "Lost by \(s) s")
        case .rounds(let a, let b):
            return won ? String(localized: "Won \(a)–\(b) in rounds") : String(localized: "Lost \(a)–\(b) in rounds")
        case .form:
            return won ? String(localized: "Same reps — won on form") : String(localized: "Same reps — lost on form")
        case .forfeit(let byMe):
            return byMe ? String(localized: "You left the battle") : String(localized: "Opponent left — win")
        case .turnMissed(let byMe):
            return byMe ? String(localized: "You missed your turn") : String(localized: "Opponent missed their turn")
        case .draw:
            return String(localized: "Draw")
        case .void:
            return String(localized: "No result")
        }
    }
}

/// Summary of a list of battles (newest first) for the History header.
public struct HistorySummary: Hashable, Sendable {
    public var wins = 0
    public var losses = 0
    public var draws = 0
    /// Close losses ("so close").
    public var closeLosses = 0
    /// Close wins ("clutch").
    public var clutchWins = 0
    /// Trophies won or lost across the ranked battles in the list.
    public var trophyNet = 0
    /// Last up to 10 results, newest first.
    public var form: [BattleRecap.Outcome] = []

    public init(_ battles: [Battle]) {
        for b in battles where b.status != "void" {
            let r = BattleRecap(b)
            switch r.outcome {
            case .win:
                wins += 1
                if r.isClose { clutchWins += 1 }
            case .loss:
                losses += 1
                if r.isClose { closeLosses += 1 }
            case .draw:
                draws += 1
            }
            if b.ranked, let t = b.myTrophies { trophyNet += t }
            if form.count < 10 { form.append(r.outcome) }
        }
    }
}
