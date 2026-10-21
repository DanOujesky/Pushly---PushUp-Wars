import Foundation

/// Battle results (doc 07 §2) — client copy of the server rules for the provisional result and live HUDs. Same as
/// `tools/reference/pushly_ref/battle.py`, SQL `app.decide_battle` and Android `BattleRules`; all pass
/// `shared/test-vectors/battles/results.json`. The server's settled result always wins.
public enum BattleRules {
    public struct Rep: Codable, Hashable, Sendable {
        /// ms since the battle start (server time)
        public var t: Int64
        public var q: Int
        public var round: Int
        public init(t: Int64, q: Int, round: Int = 0) {
            self.t = t
            self.q = q
            self.round = round
        }
    }

    public struct Side: Codable, Hashable, Sendable {
        public var reps: Int
        public var avgQuality: Int
        public var lastT: Int64?
        public var finishT: Int64?
        public var rounds: Int?
    }

    public struct RoundResult: Codable, Hashable, Sendable {
        public var a: Int
        public var b: Int
        public var winner: String?
    }

    public struct Result: Codable, Hashable, Sendable {
        /// "a" | "b" | nil (draw)
        public var winner: String?
        public var reason: String
        public var a: Side
        public var b: Side
        public var rounds: [RoundResult]?
    }

    static func avg(_ qs: [Int]) -> Int {
        qs.isEmpty ? 0 : Int((Double(qs.reduce(0, +)) / Double(qs.count) + 0.5).rounded(.down))
    }

    static func side(_ reps: [Rep]) -> Side {
        Side(reps: reps.count, avgQuality: avg(reps.map(\.q)), lastT: reps.last?.t)
    }

    static func sorted(_ reps: [Rep]) -> [Rep] {
        reps.enumerated().sorted { ($0.element.t, $0.offset) < ($1.element.t, $1.offset) }.map(\.element)
    }

    static func continuous(_ reps: [Rep], gap: Int64, cap: Int64) -> [Rep] {
        var out: [Rep] = []
        for r in sorted(reps) {
            if r.t > cap { break }
            if let last = out.last, r.t - last.t > gap { break }
            out.append(r)
        }
        return out
    }

    /// Compares fields in order; higher wins when `higher` is true. nil loses.
    static func compare(_ a: Side, _ b: Side, _ keys: [(KeyPath<Side, Int64?>, Bool)]) -> String? {
        for (key, higher) in keys {
            let x = a[keyPath: key], y = b[keyPath: key]
            if x == y { continue }
            guard let x else { return "b" }
            guard let y else { return "a" }
            return (x > y) == higher ? "a" : "b"
        }
        return nil
    }

    private static var reps: KeyPath<Side, Int64?> { \.repsValue }
    private static var quality: KeyPath<Side, Int64?> { \.qualityValue }
    private static var lastT: KeyPath<Side, Int64?> { \.lastT }
    private static var finishT: KeyPath<Side, Int64?> { \.finishT }
    private static var roundsWon: KeyPath<Side, Int64?> { \.roundsValue }

    public static func decide(mode: String, variant: [String: Int], a: [Rep], b: [Rep]) -> Result {
        switch mode {
        case "max_reps":
            let cap = Int64(variant["durationS"] ?? 60) * 1000
            let sa = side(a.filter { $0.t <= cap }), sb = side(b.filter { $0.t <= cap })
            let w = compare(sa, sb, [(reps, true), (quality, true), (lastT, false)])
            return Result(winner: w, reason: w == nil ? "draw" : "reps", a: sa, b: sb)
        case "speed":
            let target = variant["targetReps"] ?? 20
            func speedSide(_ reps: [Rep]) -> Side {
                let within = sorted(reps).filter { $0.t <= 120_000 }
                var s = side(Array(within.prefix(target)))
                s.finishT = within.count >= target ? within[target - 1].t : nil
                return s
            }
            let sa = speedSide(a), sb = speedSide(b)
            if sa.finishT != nil || sb.finishT != nil {
                let w = compare(sa, sb, [(finishT, false)])
                return Result(winner: w, reason: w == nil ? "draw" : "target", a: sa, b: sb)
            }
            let w = compare(sa, sb, [(reps, true), (lastT, false)])
            return Result(winner: w, reason: w == nil ? "draw" : "reps", a: sa, b: sb)
        case "endurance":
            let sa = side(continuous(a, gap: 3000, cap: 600_000)), sb = side(continuous(b, gap: 3000, cap: 600_000))
            let w = compare(sa, sb, [(reps, true), (lastT, false)])
            return Result(winner: w, reason: w == nil ? "draw" : "reps", a: sa, b: sb)
        case "best_of_3":
            var winsA = 0, winsB = 0
            var totalA: [Rep] = [], totalB: [Rep] = []
            var rounds: [RoundResult] = []
            for rnd in 0..<3 {
                func set(_ reps: [Rep]) -> [Rep] {
                    let rr = reps.filter { $0.round == rnd }
                    let first = rr.map(\.t).min() ?? 0
                    return continuous(rr, gap: 2000, cap: first + 90_000)
                }
                let setA = set(a), setB = set(b)
                totalA += setA
                totalB += setB
                let rw: String? = setA.count > setB.count ? "a" : setB.count > setA.count ? "b" : nil
                if rw == "a" { winsA += 1 } else if rw == "b" { winsB += 1 }
                rounds.append(RoundResult(a: setA.count, b: setB.count, winner: rw))
                if max(winsA, winsB) >= 2 { break }
            }
            var sa = side(totalA), sb = side(totalB)
            sa.rounds = winsA
            sb.rounds = winsB
            var w = compare(sa, sb, [(roundsWon, true)])
            var reason = "rounds"
            if w == nil {
                w = compare(sa, sb, [(reps, true), (quality, true)])
                reason = w == nil ? "draw" : "reps"
            }
            return Result(winner: w, reason: reason, a: sa, b: sb, rounds: rounds)
        case "turns":
            let window = Int64(5000 + min(variant["latencyMs"] ?? 0, 500))
            let events = (a.enumerated().map { (r: $0.element, p: "a", i: $0.offset) }
                          + b.enumerated().map { (r: $0.element, p: "b", i: $0.offset) })
                .sorted { ($0.r.t, $0.p, $0.i) < ($1.r.t, $1.p, $1.i) }
            var countedA: [Rep] = [], countedB: [Rep] = []
            var prev: (r: Rep, p: String)?
            var loser: String?
            var stopped = false
            for e in events {
                if let p = prev, p.p == e.p { continue }
                if let p = prev, e.r.t - p.r.t > window {
                    loser = e.p
                    stopped = true
                    break
                }
                if e.p == "a" { countedA.append(e.r) } else { countedB.append(e.r) }
                prev = (e.r, e.p)
                if countedA.count + countedB.count >= 200 {
                    stopped = true
                    break
                }
            }
            if !stopped, let p = prev { loser = p.p == "a" ? "b" : "a" }
            let sa = side(countedA), sb = side(countedB)
            if let loser {
                return Result(winner: loser == "a" ? "b" : "a", reason: "turn_missed", a: sa, b: sb)
            }
            let w = prev == nil ? nil : compare(sa, sb, [(quality, true)])
            return Result(winner: w, reason: w == nil ? "draw" : "quality", a: sa, b: sb)
        default:
            return Result(winner: nil, reason: "draw", a: side([]), b: side([]))
        }
    }
}

extension BattleRules.Side {
    var repsValue: Int64? { Int64(reps) }
    var qualityValue: Int64? { Int64(avgQuality) }
    var roundsValue: Int64? { rounds.map(Int64.init) }
}
