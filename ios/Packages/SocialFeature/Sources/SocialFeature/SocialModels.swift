import Core
import Foundation
import Observation

/// Friends screen state (doc 15 §1): lists, requests, search, feed and kudos.
@MainActor
@Observable
public final class FriendsModel {
    public private(set) var list = FriendsList.empty
    public private(set) var feed: [FeedItem] = []
    public private(set) var results: [UserCard] = []
    public private(set) var loaded = false
    public private(set) var failed = false
    /// Short status line after an action ("Request sent").
    public private(set) var notice: String?
    public var query = ""

    private let service: SocialService

    public init(service: SocialService) {
        self.service = service
    }

    public func load() async {
        do {
            async let friends = service.listFriends()
            async let events = service.feed()
            list = try JSONDecoder().decode(FriendsList.self, from: try await friends)
            feed = try JSONDecoder().decode([FeedItem].self, from: try await events)
            failed = false
        } catch {
            PLog.error("friends load failed: \(error)")
            failed = !loaded
        }
        loaded = true
    }

    public func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else {
            results = []
            return
        }
        do {
            let found = try JSONDecoder().decode([UserCard].self, from: try await service.search(q))
            if q == query.trimmingCharacters(in: .whitespaces) { results = found }   // ignore stale answers
        } catch {
            PLog.error("search failed: \(error)")
        }
    }

    public func add(_ user: UserCard) async {
        await act { _ = try await self.service.sendRequest(user.id) }
        notice = String(localized: "Request sent to \(user.username)")
        PushPrompt.request(.friends)
        await search()
    }

    public func respond(_ user: UserCard, accept: Bool) async {
        await act { _ = try await self.service.respond(user.id, accept) }
    }

    public func remove(_ user: UserCard) async {
        await act { _ = try await self.service.remove(user.id) }
    }

    public func block(_ userId: String) async {
        await act { _ = try await self.service.block(userId) }
    }

    public func unblock(_ userId: String) async {
        await act { _ = try await self.service.unblock(userId) }
    }

    /// One 👊 per event; optimistic, rolled back if the server refuses.
    public func kudos(_ item: FeedItem) async {
        guard !item.kudosByMe, let index = feed.firstIndex(where: { $0.id == item.id }) else { return }
        feed[index].kudosByMe = true
        feed[index].kudos += 1
        do {
            let count = try await service.kudos(item.id)
            if let i = feed.firstIndex(where: { $0.id == item.id }) { feed[i].kudos = count }
        } catch {
            if let i = feed.firstIndex(where: { $0.id == item.id }) {
                feed[i].kudosByMe = false
                feed[i].kudos -= 1
            }
        }
    }

    private func act(_ body: @escaping () async throws -> Void) async {
        do {
            try await body()
            notice = nil
        } catch {
            PLog.error("friends action failed: \(error)")
            notice = String(localized: "That didn't work. Please try again.")
        }
        await load()
    }

    /// Feed line, e.g. "beat the wake challenge · 30 push-ups".
    public nonisolated static func describe(_ item: FeedItem) -> String {
        switch item.kind {
        case "wake_beaten":
            String(localized: "beat the wake challenge · \(item.payload["reps"]?.int ?? 0) push-ups")
        case "achievement":
            String(localized: "unlocked \(item.payload["title"]?.string ?? "")")
        case "level_up":
            String(localized: "reached level \(item.payload["level"]?.int ?? 0)")
        case "best_set":
            String(localized: "new best set: \(item.payload["reps"]?.int ?? 0) push-ups")
        default:
            ""
        }
    }
}

/// Ranks tab state (doc 08 §4, PS-60…PS-63). Answers are cached for 60 s per board / scope / period.
@MainActor
@Observable
public final class RanksModel {
    public var board: Board = .wake
    public var scope = "global"
    public var period = "week"
    public private(set) var boards: [String: Leaderboard] = [:]
    public private(set) var loading = false
    public private(set) var failed = false

    private var fetchedAt: [String: Date] = [:]
    private let service: SocialService
    private let now: @Sendable () -> Date

    public init(service: SocialService, now: @escaping @Sendable () -> Date = { Date() }) {
        self.service = service
        self.now = now
    }

    var key: String { "\(board.rawValue)/\(scope)/\(period)" }
    public var current: Leaderboard? { boards[key] }

    public func select(board: Board) async {
        self.board = board
        if !board.periods.contains(period) { period = board.defaultPeriod }
        await load()
    }

    public func select(scope: String) async {
        self.scope = scope
        await load()
    }

    public func select(period: String) async {
        self.period = period
        await load()
    }

    public func load(force: Bool = false) async {
        let k = key
        if !force, let at = fetchedAt[k], now().timeIntervalSince(at) < 60 { return }
        loading = true
        defer { loading = false }
        do {
            let data = try await service.leaderboard(board.rawValue, scope, period)
            boards[k] = try JSONDecoder().decode(Leaderboard.self, from: data)
            fetchedAt[k] = now()
            failed = false
        } catch {
            PLog.error("leaderboard load failed: \(error)")
            failed = boards[k] == nil
        }
    }

    /// The own row to pin at the bottom when it isn't visible in the top list.
    public var pinnedMe: Leaderboard.Row? {
        guard let board = current, let me = board.me, !board.rows.contains(where: \.isMe) else { return nil }
        return board.around.first(where: \.isMe)
            ?? .init(rank: me.rank, score: me.score, isMe: true, user: .init(username: String(localized: "You")))
    }
}
