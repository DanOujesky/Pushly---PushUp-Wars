import Foundation
import Testing
@testable import BattleFeature

/// Practice bots (D-063): always shown as bots, started through `start_bot_battle`, rematch keeps the level.
@MainActor
struct PracticeBotTests {
    nonisolated private static func battleJSON(bot: String?) throws -> Data {
        var obj = try JSONSerialization.jsonObject(with: RepoFile.data("shared/contracts/fixtures/battle.json")) as? [String: Any] ?? [:]
        obj["type"] = "ghost"
        obj["ranked"] = false
        obj["ghost"] = true
        obj["bot"] = bot ?? NSNull()
        obj["opponent"] = ["username": bot.map { "Bot · " + $0.capitalized } ?? "Ghost"]
        return try JSONSerialization.data(withJSONObject: obj)
    }

    private final class Calls: @unchecked Sendable {
        var bot: [(String, String?)] = []
    }

    nonisolated private static func service(_ calls: Calls) -> BattleService {
        let none: @Sendable () async throws -> Data = { throw CancellationError() }
        return BattleService(
            invites: none, friends: none, invite: { _, _, _ in throw CancellationError() },
            respond: { _, _ in throw CancellationError() }, join: { _ in throw CancellationError() }, status: none,
            leaveQueue: {}, get: { _ in throw CancellationError() }, ready: { _ in throw CancellationError() },
            push: { _, _ in }, finish: { _ in throw CancellationError() }, forfeit: { _ in throw CancellationError() },
            history: none, ghost: { _ in throw CancellationError() },
            bot: { mode, level in
                calls.bot.append((mode, level))
                return try battleJSON(bot: level ?? "rookie")
            })
    }

    @Test func botsAreAlwaysMarked() throws {
        let bot = try JSONDecoder().decode(Battle.self, from: Self.battleJSON(bot: "athlete"))
        #expect(bot.opponentDisplayName == "🤖 Bot · Athlete")
        let ghost = try JSONDecoder().decode(Battle.self, from: Self.battleJSON(bot: nil))
        #expect(ghost.opponentDisplayName == "Ghost")
    }

    @Test func practiceStartsABotBattle() async throws {
        let calls = Calls()
        let model = BattleHubModel(service: Self.service(calls))
        await model.practice(.speed, level: .pro)
        #expect(calls.bot.count == 1 && calls.bot.first?.0 == "speed" && calls.bot.first?.1 == "pro")
        #expect(model.active?.bot == "pro")
    }

    @Test func rematchAgainstABotKeepsTheLevel() async throws {
        let calls = Calls()
        let model = BattleHubModel(service: Self.service(calls))
        let finished = try JSONDecoder().decode(Battle.self, from: Self.battleJSON(bot: "champion"))
        await model.rematch(finished)
        #expect(calls.bot.first?.1 == "champion")
    }

    @Test func levelsOrderedWeakestFirst() {
        #expect(BotLevel.allCases.map(\.rawValue) == ["beginner", "rookie", "athlete", "pro", "champion"])
    }
}
