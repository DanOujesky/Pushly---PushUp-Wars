import Foundation

/// What the battle announcer says / plays (doc 07 §6 "more action", D-066). Pure rules — the same on Android
/// (`BattleCallouts.kt`), unit-tested on both.
public enum BattleCallout: Equatable, Sendable {
    case countdown(Int)
    case go
    /// The opponent did a rep (sound only).
    case opponentRep
    case tookLead
    case lostLead
    case tied
    /// Fell this many reps behind (3, 5, 10 — each once until you're level again).
    case behind(Int)
    case secondsLeft(Int)
}

public struct BattleAnnouncer: Sendable {
    /// Voice lines closer than this are dropped (sounds and the clock always play).
    public static let minVoiceGapMs: Int64 = 2500
    static let behindMilestones = [3, 5, 10]
    static let timeMarks = [30, 10]

    private var lastCountdown: Int?
    private var wentLive = false
    private var lastTheirs = 0
    private var lastSign = 0
    private var announcedBehind: Set<Int> = []
    private var announcedTimes: Set<Int> = []
    private var lastVoiceAt: Int64 = .min / 2

    public init() {}

    /// Before GO: one call per second of the countdown.
    public mutating func countdown(_ seconds: Int) -> [BattleCallout] {
        guard seconds != lastCountdown, (1...3).contains(seconds) else { return [] }
        lastCountdown = seconds
        return [.countdown(seconds)]
    }

    /// While live. `mine` / `theirs` = the scores that decide the battle right now (nil = no lead in this mode, e.g.
    /// Turns), `secondsLeft` = the mode clock, `nowMs` = monotonic ms.
    public mutating func live(mine: Int?, theirs: Int?, theirTotal: Int, secondsLeft: Int?, nowMs: Int64) -> [BattleCallout] {
        var out: [BattleCallout] = []
        if !wentLive {
            wentLive = true
            out.append(.go)
            lastVoiceAt = nowMs
        }
        if theirTotal > lastTheirs { out.append(.opponentRep) }
        lastTheirs = theirTotal

        if let mine, let theirs {
            let diff = mine - theirs
            let sign = diff > 0 ? 1 : diff < 0 ? -1 : 0
            var voice: BattleCallout?
            if sign != lastSign {
                voice = sign > 0 ? .tookLead : sign < 0 ? .lostLead : .tied
                lastSign = sign
            }
            if diff >= 0 { announcedBehind.removeAll() }
            if let milestone = Self.behindMilestones.last(where: { -diff >= $0 }), !announcedBehind.contains(milestone) {
                announcedBehind.formUnion(Self.behindMilestones.filter { $0 <= milestone })
                voice = .behind(milestone)
            }
            if let voice, nowMs - lastVoiceAt >= Self.minVoiceGapMs {
                out.append(voice)
                lastVoiceAt = nowMs
            }
        }
        if let s = secondsLeft, let mark = Self.timeMarks.first(where: { $0 == s }), !announcedTimes.contains(mark) {
            announcedTimes.insert(mark)
            out.append(.secondsLeft(mark))
            lastVoiceAt = nowMs
        }
        return out
    }

    public static func text(_ c: BattleCallout) -> String? {
        switch c {
        case let .countdown(n): "\(n)"
        case .go: String(localized: "Go!")
        case .opponentRep: nil
        case .tookLead: String(localized: "You're in the lead!")
        case .lostLead: String(localized: "They're ahead — push!")
        case .tied: String(localized: "All square!")
        case let .behind(n): String(localized: "\(n) behind — dig in!")
        case let .secondsLeft(s): s >= 30 ? String(localized: "Thirty seconds left!") : String(localized: "Ten seconds — empty the tank!")
        }
    }
}
