import Core
import Foundation
import Observation

/// Clan tab state (doc 09 §4–5).
@MainActor
@Observable
public final class ClanModel {
    public private(set) var home: ClanHome?
    public private(set) var loaded = false
    public private(set) var failed = false
    public private(set) var results: [ClanSummary] = []
    public private(set) var messages: [ClanMessage] = []
    public private(set) var notice: String?
    public private(set) var busy = false
    public var query = ""

    private let service: ClanService

    public init(service: ClanService) {
        self.service = service
    }

    public var myRole: ClanRole? { home?.summary.myRole.flatMap(ClanRole.init(rawValue:)) }

    public func load() async {
        do {
            let data = try await service.home()
            home = try JSONDecoder().decode(ClanHome?.self, from: data)
            failed = false
            if home == nil, results.isEmpty { await search() }
        } catch {
            PLog.error("clan load failed: \(error)")
            failed = !loaded
        }
        loaded = true
    }

    /// Empty query = recommended clans.
    public func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        do {
            let found = try JSONDecoder().decode([ClanSummary].self, from: try await service.search(q))
            if q == query.trimmingCharacters(in: .whitespaces) { results = found }
        } catch {
            PLog.error("clan search failed: \(error)")
        }
    }

    public func create(name: String, tag: String, description: String, policy: String) async -> Bool {
        busy = true
        defer { busy = false }
        do {
            _ = try await service.create(name, tag.uppercased(), description, policy)
            notice = nil
            await load()
            return true
        } catch {
            notice = Self.message(for: error)
            return false
        }
    }

    public func join(_ clan: ClanSummary) async {
        await act {
            let outcome = try await self.service.join(clan.id, nil)
            self.notice = outcome == "requested" ? String(localized: "Request sent to \(clan.name)") : nil
        }
        await search()
    }

    public func respond(_ userId: String, accept: Bool) async { await act { _ = try await self.service.respond(userId, accept) } }
    public func leave() async { await act { _ = try await self.service.leave() } }
    public func kick(_ userId: String) async { await act { try await self.service.kick(userId) } }
    public func setRole(_ userId: String, _ role: ClanRole) async { await act { try await self.service.setRole(userId, role.rawValue) } }
    public func transfer(_ userId: String) async { await act { try await self.service.transfer(userId) } }

    public func loadMessages() async {
        do {
            messages = try JSONDecoder().decode([ClanMessage].self, from: try await service.messages(nil))
        } catch {
            PLog.error("clan chat load failed: \(error)")
        }
    }

    public func send(_ body: String, kind: String = "text") async -> Bool {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        do {
            try await service.send(text, kind)
            notice = nil
            await loadMessages()
            return true
        } catch {
            notice = Self.message(for: error)
            return false
        }
    }

    private func act(_ body: @escaping () async throws -> Void) async {
        busy = true
        defer { busy = false }
        do {
            try await body()
        } catch {
            notice = Self.message(for: error)
        }
        await load()
    }

    /// Server hints (P0001/22023 + hint) → friendly text.
    nonisolated static func message(for error: Error) -> String {
        let text = String(describing: error)
        if text.contains("rate_limited") || text.contains("rate limited") { return String(localized: "Slow down a little and try again.") }
        if text.contains("taken") { return String(localized: "That name or tag is taken.") }
        if text.contains("invalid_name") { return String(localized: "Pick another clan name (3–24 characters).") }
        if text.contains("invalid_tag") { return String(localized: "The tag needs 3–5 letters or digits.") }
        if text.contains("full") { return String(localized: "This clan is full.") }
        if text.contains("requirements") { return String(localized: "You don't meet this clan's requirements yet.") }
        if text.contains("already_in_clan") { return String(localized: "Leave your clan first.") }
        return String(localized: "That didn't work. Please try again.")
    }
}
