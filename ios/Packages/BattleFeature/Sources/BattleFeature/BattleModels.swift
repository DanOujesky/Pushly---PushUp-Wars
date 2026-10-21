import Core
import Foundation
import Observation
import RepEngine
import WakeFlowFeature

/// Battle tab hub (doc 07 §3, §8): quick match queue, friend invites, history. Opens a battle via `active`.
@MainActor
@Observable
public final class BattleHubModel {
    public private(set) var invites = BattleInvites(incoming: [], outgoing: [])
    public private(set) var history: [Battle] = []
    public private(set) var friends: [FriendPick] = []
    public private(set) var queuedMode: BattleMode?
    public private(set) var waitedS = 0
    public private(set) var notice: String?
    /// Set when a battle is ready to play (matched or invite accepted) — the view presents it.
    public var active: Battle?

    let service: BattleService
    private var poller: Task<Void, Never>?

    public init(service: BattleService) {
        self.service = service
    }

    public func load() async {
        let decoder = JSONDecoder()
        if let data = try? await service.invites(), let inv = try? decoder.decode(BattleInvites.self, from: data) { invites = inv }
        if let data = try? await service.history(), let h = try? decoder.decode([Battle].self, from: data) { history = h }
        if let data = try? await service.friends(), let list = try? decoder.decode(FriendsPayload.self, from: data) {
            friends = list.friends
        }
    }

    private struct FriendsPayload: Decodable { let friends: [FriendPick] }

    public func quickMatch(_ mode: BattleMode) async {
        do {
            let status = try JSONDecoder().decode(MatchmakingStatus.self, from: try await service.join(mode.rawValue))
            if let battle = status.battle {
                active = battle
                return
            }
            queuedMode = mode
            waitedS = 0
            startPolling()
        } catch {
            notice = String(localized: "Couldn't join the queue. Please try again.")
        }
    }

    public func cancelQueue() async {
        poller?.cancel()
        queuedMode = nil
        try? await service.leaveQueue()
    }

    private func startPolling() {
        poller?.cancel()
        poller = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, self.queuedMode != nil else { return }
                guard let data = try? await self.service.status(),
                      let status = try? JSONDecoder().decode(MatchmakingStatus.self, from: data) else { continue }
                if let battle = status.battle {
                    self.queuedMode = nil
                    self.active = battle
                    return
                }
                if !status.queued {
                    self.queuedMode = nil
                    self.notice = String(localized: "Nobody to battle right now. Try again in a minute or challenge a friend.")
                    return
                }
                self.waitedS = status.waitedS ?? self.waitedS + 2
            }
        }
    }

    public func challenge(_ friend: FriendPick, mode: BattleMode, ranked: Bool) async {
        do {
            _ = try await service.invite(friend.id, mode.rawValue, ranked)
            notice = String(localized: "Challenge sent to \(friend.username). It expires in 5 minutes.")
            await load()
            watchOutgoing()
        } catch {
            notice = String(localized: "Couldn't send the challenge.")
        }
    }

    /// Waits for an accepted outgoing invite, then opens the battle.
    private func watchOutgoing() {
        poller?.cancel()
        poller = Task { [weak self] in
            for _ in 0..<100 {
                try? await Task.sleep(for: .seconds(3))
                guard let self, !Task.isCancelled else { return }
                guard let data = try? await self.service.invites(),
                      let inv = try? JSONDecoder().decode(BattleInvites.self, from: data) else { continue }
                self.invites = inv
                if let id = inv.outgoing.first(where: { $0.status == "accepted" && $0.battleId != nil })?.battleId,
                   let data = try? await self.service.get(id),
                   let battle = try? JSONDecoder().decode(Battle.self, from: data), !battle.isOver {
                    self.active = battle
                    return
                }
            }
        }
    }

    public func accept(_ invite: BattleInvites.Incoming) async {
        do {
            active = try JSONDecoder().decode(Battle.self, from: try await service.respond(invite.id, true))
        } catch {
            notice = String(localized: "This challenge has expired.")
        }
        await load()
    }

    public func decline(_ invite: BattleInvites.Incoming) async {
        _ = try? await service.respond(invite.id, false)
        await load()
    }
}

/// One live battle (doc 07 §4): ready check → server countdown → live counting with rep events in server time →
/// finish (rep log + battle_finish) → settled result. Opponent score from polling `get_battle` once a second.
@MainActor
@Observable
public final class LiveBattleModel {
    public enum Phase: Equatable {
        case lobby, countdown(Int), live, waiting, done, cancelled
    }

    public private(set) var battle: Battle
    public private(set) var phase: Phase = .lobby
    public private(set) var myReps: [BattleRules.Rep] = []
    public private(set) var secondsLeft: Int?
    public let reps: RepSessionModel

    private let service: BattleService
    private let sessions: SessionServices?
    private var anchor: ServerAnchor?
    private var readySent = false
    private var finished = false
    private var pending: [PushRep] = []
    private var ticker: Task<Void, Never>?
    private var lastPoll: Int64 = 0
    private let sessionId = UUID().uuidString.lowercased()

    struct PushRep: Encodable {
        let round: Int
        let i: Int
        let t: Int64
        let q: Int
    }

    public init(battle: Battle, service: BattleService, sessions: SessionServices?) {
        self.battle = battle
        self.service = service
        self.sessions = sessions
        reps = RepSessionModel(mode: .open) { _ in }
        reps.onCounted = { [weak self] total in self?.counted(total) }
    }

    var mode: String { battle.mode }

    /// Server time now (anchor + monotonic), else the phone clock.
    var serverNowMs: Int64 {
        if let anchor { return anchor.serverMs + (reps.monotonicNowMs - anchor.monotonicMs) }
        return Int64(reps.nowDate.timeIntervalSince1970 * 1000)
    }

    var startMs: Int64? {
        guard let s = battle.startAt else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
        return date.map { Int64($0.timeIntervalSince1970 * 1000) }
    }

    public func start() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            if let sessions = self?.sessions { self?.anchor = await sessions.anchor() }
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    public func stop() {
        ticker?.cancel()
        ticker = nil
    }

    func tick() async {
        let now = serverNowMs
        if now - lastPoll >= 1000 {
            lastPoll = now
            if let data = try? await service.get(battle.id), let fresh = try? JSONDecoder().decode(Battle.self, from: data) {
                battle = fresh
            }
        }
        switch battle.status {
        case "cancelled", "void":
            phase = .cancelled
            stop()
            return
        case "settled":
            phase = .done
            stop()
            return
        default:
            break
        }
        if phase == .waiting || phase == .done { return }
        if !readySent, reps.state != .notReady, ["lobby", "ready_check"].contains(battle.status) {
            readySent = true
            if let data = try? await service.ready(battle.id), let b = try? JSONDecoder().decode(Battle.self, from: data) { battle = b }
        }
        guard let start = startMs else { return }
        let t = now - start
        if t < 0 {
            phase = .countdown(Int((-t + 999) / 1000))
            return
        }
        if phase != .live {
            phase = .live
            reps.beginTimeline()
        }
        secondsLeft = remainingSeconds(t)
        if shouldEnd(t) {
            await finish()
        } else {
            await flush()
        }
    }

    private func remainingSeconds(_ t: Int64) -> Int? {
        switch mode {
        case "max_reps": Int(max(0, Int64(battle.variant["durationS"] ?? 60) * 1000 - t) / 1000)
        case "speed": Int(max(0, 120_000 - t) / 1000)
        default: nil
        }
    }

    func shouldEnd(_ t: Int64) -> Bool {
        switch mode {
        case "max_reps":
            return t >= Int64(battle.variant["durationS"] ?? 60) * 1000
        case "speed":
            let target = battle.variant["targetReps"] ?? 20
            return myReps.count >= target || battle.theirScore >= target || t >= 120_000
        case "endurance":
            if let last = myReps.last { return t - last.t > 3000 }
            return t >= 600_000
        default:
            return t >= 360_000
        }
    }

    private func counted(_ total: Int) {
        guard phase == .live, let start = startMs else { return }
        let rep = BattleRules.Rep(t: serverNowMs - start, q: reps.lastQuality ?? 0)
        myReps.append(rep)
        pending.append(PushRep(round: 0, i: total, t: rep.t, q: rep.q))
    }

    private func flush() async {
        guard !pending.isEmpty, let body = try? JSONEncoder().encode(pending) else { return }
        let batch = pending
        pending = []
        do {
            try await service.push(battle.id, body)
        } catch {
            pending = batch + pending     // retry with the next tick
        }
    }

    func finish() async {
        guard !finished else { return }
        finished = true
        phase = .waiting
        reps.finish(outcome: "completed")
        await flush()
        if let sessions {
            sessions.uploader.enqueue(reps.repLog(sessionId: sessionId, context: "battle", anchor: anchor,
                                                  appVersion: sessions.appVersion, battleId: battle.id))
        }
        if let data = try? await service.finish(battle.id), let b = try? JSONDecoder().decode(Battle.self, from: data) {
            battle = b
            if b.status == "settled" { phase = .done }
        }
    }

    public func leave() async {
        reps.finish(outcome: "gaveUp")
        if let data = try? await service.forfeit(battle.id), let b = try? JSONDecoder().decode(Battle.self, from: data) {
            battle = b
        }
        phase = battle.status == "cancelled" ? .cancelled : .done
        stop()
    }

    /// What the result screen shows until the server settles (same rules as the server).
    public var provisional: BattleRules.Result {
        let mine = myReps
        let none: [BattleRules.Rep] = []
        return battle.me == "a"
            ? BattleRules.decide(mode: mode, variant: battle.variant, a: mine, b: none)
            : BattleRules.decide(mode: mode, variant: battle.variant, a: none, b: mine)
    }
}
