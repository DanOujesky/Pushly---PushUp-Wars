import Core
import DesignSystem
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
    public private(set) var warHistory: [ClanWarRecord] = []
    public private(set) var chests: WarChests?
    /// XP from the chest just opened (for the reveal).
    public private(set) var openedXP: Int?
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
            await loadWarExtras()
        } catch {
            PLog.error("clan load failed: \(error)")
            failed = !loaded
        }
        loaded = true
    }

    /// War history (for the clan page) and my War Chests (they stay mine after leaving a clan).
    public func loadWarExtras() async {
        let decoder = JSONDecoder()
        if home != nil, let data = try? await service.warHistory(), let wars = try? decoder.decode([ClanWarRecord].self, from: data) {
            warHistory = wars
        } else if home == nil {
            warHistory = []
        }
        if let data = try? await service.chests(), let c = try? decoder.decode(WarChests.self, from: data) { chests = c }
    }

    public func open(_ chest: WarChests.Chest) async {
        struct Opened: Decodable { let xp: Int }
        do {
            let opened = try JSONDecoder().decode(Opened.self, from: try await service.openChest(chest.id))
            openedXP = opened.xp
            notice = nil
        } catch {
            notice = Self.message(for: error)
        }
        await loadWarExtras()
    }

    public func dismissOpened() { openedXP = nil }

    /// Rally the clan (D-068): everyone gets a push and a chat line; once per clan every 6 hours.
    public func rally() async {
        do {
            _ = try await service.rally()
            notice = String(localized: "Rally sent — your clan has been called to arms!")
            await load()
        } catch {
            let text = String(describing: error)
            notice = text.contains("rally_cooldown") || text.contains("cooldown")
                ? String(localized: "Your clan was rallied less than 6 hours ago.")
                : Self.message(for: error)
        }
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

    /// The server picks the clan's tag from the name (D-075).
    public func create(name: String, description: String, policy: String,
                       badge: ClanBadgeStyle = ClanBadgeStyle()) async -> Bool {
        busy = true
        defer { busy = false }
        do {
            _ = try await service.create(name.trimmingCharacters(in: .whitespaces), "", description, policy, badge.json)
            notice = nil
            PushPrompt.request(.clan)
            await load()
            return true
        } catch {
            notice = Self.message(for: error)
            return false
        }
    }

    /// Leaders / co-leaders: badge, description, join policy (nil = unchanged). True when saved.
    public func update(badge: ClanBadgeStyle?, description: String?, policy: String?) async -> Bool {
        busy = true
        defer { busy = false }
        do {
            _ = try await service.update(badge?.json, description, policy)
            notice = nil
            await load()
            return true
        } catch {
            notice = Self.message(for: error)
            return false
        }
    }

    public func clearNotice() { notice = nil }

    public func join(_ clan: ClanSummary) async {
        await act {
            let outcome = try await self.service.join(clan.id, nil)
            self.notice = outcome == "requested" ? String(localized: "Request sent to \(clan.name)") : nil
            PushPrompt.request(.clan)
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
        if text.contains("pro_required") { return String(localized: "That emblem is part of Pushly Pro.") }
        if text.contains("invalid_badge") { return String(localized: "That badge isn't available.") }
        return String(localized: "That didn't work. Please try again.")
    }
}
