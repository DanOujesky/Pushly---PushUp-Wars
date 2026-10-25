import Core
import Foundation

/// Full-screen ads shown on this device in the last 7 days (for the AdsGate caps), persisted in UserDefaults.
struct AdHistory {
    static let key = "ads.shown.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var shown: [AdsGate.Shown] {
        guard let data = defaults.data(forKey: Self.key),
              let list = try? JSONDecoder().decode([AdsGate.Shown].self, from: data) else { return [] }
        return list
    }

    func record(_ placement: String, atMs: Int64) {
        let week: Int64 = 7 * 24 * 3600 * 1000
        let list = (shown + [AdsGate.Shown(placement: placement, atMs: atMs)]).filter { atMs - $0.atMs < week }
        if let data = try? JSONEncoder().encode(list) { defaults.set(data, forKey: Self.key) }
    }
}

/// Builds the AdsGate context from what the app is doing right now (doc 13 §1).
@MainActor
enum AdContext {
    static func current(screen: String = "other", history: AdHistory = AdHistory(), now: Date = Date()) -> AdsGate.Context {
        var ctx = AdsGate.Context()
        ctx.isPro = Monetization.isPro
        ctx.wakeActive = AppActivity.wakeActive
        ctx.lastWakeEndedMs = AppActivity.lastWakeEndedAt.map { Int64($0.timeIntervalSince1970 * 1000) }
        ctx.cameraActive = AppActivity.cameraActive
        ctx.battlePhase = AppActivity.battlePhase
        ctx.screen = screen
        ctx.completedSessions = AppActivity.completedSessions
        ctx.nowMs = Int64(now.timeIntervalSince1970 * 1000)
        ctx.shown = history.shown
        ctx.battlesSinceInterstitial = AppActivity.battlesSinceInterstitial
        return ctx
    }
}
