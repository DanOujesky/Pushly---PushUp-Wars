import Foundation
import Testing
@testable import AlarmFeature

/// Wake tab rules (D-079) — same expectations as Android WakeTabRulesTest.
struct WakeTabRulesTests {
    private func summary() throws -> WakeSummary {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("shared/contracts/fixtures/wake_summary.json"))
        return try JSONDecoder().decode(WakeSummary.self, from: data)
    }

    @Test func weekCounts() throws {
        let s = try summary()
        #expect(WakeWeek.dates(s).first == "2026-10-19")
        #expect(WakeWeek.dates(s).count == 7)
        #expect(WakeWeek.beaten(s) == 1)        // Tue beaten; Sat/Sun of last week don't count
        #expect(WakeWeek.challenges(s) == 2)    // Mon missed + Tue beaten
    }

    @Test func greetingBuckets() {
        #expect(WakeGreeting.bucket(hour: 6) == "morning")
        #expect(WakeGreeting.bucket(hour: 12) == "afternoon")
        #expect(WakeGreeting.bucket(hour: 20) == "evening")
        #expect(WakeGreeting.bucket(hour: 2) == "night")
    }

    @Test func countdownFraction() {
        #expect(WakeCountdown.fraction(secondsLeft: 86400 * 2) == 0)
        #expect(WakeCountdown.fraction(secondsLeft: 43200) == 0.5)
        #expect(WakeCountdown.fraction(secondsLeft: -5) == 1)
    }
}
