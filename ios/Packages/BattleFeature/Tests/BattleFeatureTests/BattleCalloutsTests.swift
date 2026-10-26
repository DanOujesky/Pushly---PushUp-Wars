import Testing
@testable import BattleFeature

/// Battle announcer rules (D-066) — same cases as Android BattleCalloutsTest.
struct BattleCalloutsTests {
    @Test func countdownOncePerSecondThenGo() {
        var a = BattleAnnouncer()
        #expect(a.countdown(7).isEmpty)                 // GET READY: silent (D-081)
        #expect(a.countdown(5) == [.countdown(5)])
        #expect(a.countdown(3) == [.countdown(3)])
        #expect(a.countdown(3).isEmpty)
        #expect(a.countdown(2) == [.countdown(2)])
        #expect(a.live(mine: 0, theirs: 0, theirTotal: 0, secondsLeft: 60, nowMs: 0) == [.go])
    }

    @Test func countdownStages() {
        #expect(BattleCountdown.stage(secondsLeft: 8) == .getReady)
        #expect(BattleCountdown.stage(secondsLeft: 6) == .getReady)
        #expect(BattleCountdown.stage(secondsLeft: 5) == .count(5))
        #expect(BattleCountdown.stage(secondsLeft: 1) == .count(1))
        #expect(BattleCountdown.stage(secondsLeft: 0) == .count(1))
    }

    @Test func leadChangesAndOpponentReps() {
        var a = BattleAnnouncer()
        _ = a.live(mine: 0, theirs: 0, theirTotal: 0, secondsLeft: 60, nowMs: 0)
        #expect(a.live(mine: 1, theirs: 0, theirTotal: 0, secondsLeft: 59, nowMs: 3000) == [.tookLead])
        #expect(a.live(mine: 1, theirs: 1, theirTotal: 1, secondsLeft: 58, nowMs: 6000) == [.opponentRep, .tied])
        // Too soon after the last line: sound only.
        #expect(a.live(mine: 1, theirs: 2, theirTotal: 2, secondsLeft: 58, nowMs: 7000) == [.opponentRep])
    }

    @Test func behindMilestonesOnceUntilLevel() {
        var a = BattleAnnouncer()
        _ = a.live(mine: 0, theirs: 0, theirTotal: 0, secondsLeft: 60, nowMs: 0)
        _ = a.live(mine: 0, theirs: 1, theirTotal: 1, secondsLeft: 59, nowMs: 3000)
        #expect(a.live(mine: 0, theirs: 3, theirTotal: 3, secondsLeft: 55, nowMs: 6000) == [.opponentRep, .behind(3)])
        #expect(a.live(mine: 1, theirs: 4, theirTotal: 4, secondsLeft: 54, nowMs: 9000) == [.opponentRep])
        #expect(a.live(mine: 1, theirs: 6, theirTotal: 6, secondsLeft: 50, nowMs: 12000) == [.opponentRep, .behind(5)])
    }

    @Test func clockMarksOnce() {
        var a = BattleAnnouncer()
        _ = a.live(mine: nil, theirs: nil, theirTotal: 0, secondsLeft: 31, nowMs: 0)
        #expect(a.live(mine: nil, theirs: nil, theirTotal: 0, secondsLeft: 30, nowMs: 1000) == [.secondsLeft(30)])
        #expect(a.live(mine: nil, theirs: nil, theirTotal: 0, secondsLeft: 30, nowMs: 1200).isEmpty)
        #expect(a.live(mine: nil, theirs: nil, theirTotal: 0, secondsLeft: 10, nowMs: 21000) == [.secondsLeft(10)])
    }
}
