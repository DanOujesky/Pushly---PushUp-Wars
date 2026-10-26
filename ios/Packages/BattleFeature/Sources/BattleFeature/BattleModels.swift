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
    public private(set) var seasons: [SeasonResult] = []
    /// Trophies, league, rank and record for the arena header (nil until loaded / offline).
    public private(set) var arena: ArenaStatus?
    public private(set) var queuedMode: BattleMode?
    public private(set) var waitedS = 0
    public private(set) var notice: String?
    /// Offered when nobody is in the queue: practise against a bot in this mode instead (D-063).
    public private(set) var botOffer: BattleMode?
    /// Set when a battle is ready to play (matched or invite accepted) — the view presents it.
    public var active: Battle?
    /// Leaderboard sheet (D-075): trophies (global / friends) and clans.
    public private(set) var trophyBoard: TrophyBoard?
    public private(set) var clanBoard: [ClanBoardRow] = []
    public private(set) var boardFailed = false
    /// Seconds in the queue before a ranked Arena Bot steps in (D-075; the server allows it from 9 s).
    nonisolated public static let arenaBotAfterS = 10
    private var queuedAt: Date?

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
        if let data = try? await service.seasons(), let s = try? decoder.decode([SeasonResult].self, from: data) { seasons = s }
        if let data = try? await service.stats(), let a = try? decoder.decode(ArenaStatus.self, from: data) { arena = a }
    }

    /// Rematch (doc 08 §5): friend battles — same mode, as a new (friendly) challenge; bots — same level.
    public func rematch(_ battle: Battle) async {
        if battle.bot == "arena", let mode = BattleMode(wire: battle.mode) {
            await quickMatch(mode)
            return
        }
        if let level = battle.bot, let mode = BattleMode(wire: battle.mode) {
            await practice(mode, level: BotLevel(rawValue: level))
            return
        }
        guard ["friendly", "friend_ranked"].contains(battle.type), let id = battle.opponent.id,
              let mode = BattleMode(wire: battle.mode) else { return }
        await challenge(FriendPick(id: id, username: battle.opponent.username, avatarPreset: battle.opponent.avatarPreset),
                        mode: mode)
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
            botOffer = nil
            waitedS = 0
            queuedAt = Date()
            startPolling()
        } catch {
            notice = String(localized: "Couldn't join the queue. Please try again.")
        }
    }

    /// Practice against a labelled bot (D-063): no trophies, starts at once.
    public func practice(_ mode: BattleMode, level: BotLevel?) async {
        botOffer = nil
        do {
            active = try JSONDecoder().decode(Battle.self, from: try await service.bot(mode.rawValue, level?.rawValue))
            notice = nil
        } catch {
            notice = String(localized: "Couldn't start the practice battle. Please try again.")
        }
    }

    /// Leaves the queue and fights a bot in the same mode instead.
    public func practiceInsteadOfWaiting() async {
        guard let mode = queuedMode ?? botOffer else { return }
        await cancelQueue()
        await practice(mode, level: nil)
    }

    public func clearNotice() { notice = nil }

    // MARK: leaderboard (D-075)

    public func loadTrophyBoard(scope: String) async {
        do {
            trophyBoard = try JSONDecoder().decode(TrophyBoard.self, from: try await service.trophyBoard(scope))
            boardFailed = false
        } catch {
            boardFailed = true
        }
    }

    public func loadClanBoard() async {
        struct Payload: Decodable { let rows: [ClanBoardRow] }
        do {
            clanBoard = try JSONDecoder().decode(Payload.self, from: try await service.clanBoard()).rows
            boardFailed = false
        } catch {
            boardFailed = true
        }
    }

    // MARK: adding friends (D-072)

    /// Username search results in the Friends sheet.
    public private(set) var userHits: [UserHit] = []

    public func searchUsers(_ query: String) async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else {
            userHits = []
            return
        }
        guard let data = try? await service.searchUsers(q), let hits = try? JSONDecoder().decode([UserHit].self, from: data) else { return }
        userHits = hits
    }

    public func addFriend(_ user: UserHit) async {
        do {
            try await service.addFriend(user.id)
            if let i = userHits.firstIndex(of: user) { userHits[i].relation = "outgoing" }
            notice = String(localized: "Friend request sent to \(user.username).")
            PushPrompt.request(.friends)
        } catch {
            notice = String(localized: "Couldn't send the friend request.")
        }
    }

    /// Incoming challenges that are still open.
    public var openInvites: [BattleInvites.Incoming] { invites.incoming }

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
                    self.botOffer = self.queuedMode
                    self.queuedMode = nil
                    self.notice = String(localized: "Nobody to battle right now. Try again in a minute or challenge a friend.")
                    return
                }
                self.waitedS = status.waitedS ?? self.waitedS + 2
                if let mode = self.queuedMode, mode.quickMatch, let since = self.queuedAt,
                   Date().timeIntervalSince(since) >= Double(Self.arenaBotAfterS),
                   let data = try? await self.service.arenaBot(),
                   let battle = try? JSONDecoder().decode(Battle.self, from: data) {
                    // nobody near your trophies right now: a ranked Arena Bot at your level (D-075)
                    self.queuedMode = nil
                    self.active = battle
                    return
                }
            }
        }
    }

    /// Friend battles are always friendly — no trophies (D-071).
    public func challenge(_ friend: FriendPick, mode: BattleMode) async {
        do {
            _ = try await service.invite(friend.id, mode.rawValue, false)
            notice = String(localized: "Challenge sent to \(friend.username). It expires in 5 minutes.")
            PushPrompt.request(.battles)
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
    /// Split-screen video with the opponent (doc 07 §5); people only — no video against ghosts and bots.
    public let video = BattleVideo()
    /// Last announcer line shown big on screen (D-066), with a counter so the same line can flash again.
    public private(set) var callout: (text: String, positive: Bool, id: Int)?

    private let sounds = RepSounds()
    private var announcer = BattleAnnouncer()

    private let service: BattleService
    private let sessions: SessionServices?
    private var anchor: ServerAnchor?
    private var readySent = false
    private var finished = false
    private var pending: [PushRep] = []
    /// Turns: my reps done while it looked like the opponent's turn (see `promoteTurnReps`).
    private var unconfirmed: [BattleRules.Rep] = []
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
        reps = RepSessionModel(mode: .open, speakCount: false, allowFront: false) { _ in }
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
        if battle.ghost != true, video.state == .off {
            Task { [weak self] in
                guard let self else { return }
                await self.video.start(battleId: self.battle.id, service: self.service, reps: self.reps)
            }
        }
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
        if video.state != .off { Task { await video.stop() } }
    }

    func tick() async {
        let now = serverNowMs
        if now - lastPoll >= 1000 {
            lastPoll = now
            if let data = try? await service.get(battle.id), let fresh = try? JSONDecoder().decode(Battle.self, from: data) {
                battle = fresh
                promoteTurnReps()
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
            let n = Int((-t + 999) / 1000)
            phase = .countdown(n)
            handle(announcer.countdown(n))
            return
        }
        if phase != .live {
            phase = .live
            reps.beginTimeline()
        }
        secondsLeft = remainingSeconds(t)
        let score = lead
        handle(announcer.live(mine: score?.mine, theirs: score?.theirs, theirTotal: battle.theirScore,
                              secondsLeft: secondsLeft, nowMs: reps.monotonicNowMs))
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
        case "best_of_3": Int((BattleHud.bo3Clock(t).msLeft + 999) / 1000)
        default: nil
        }
    }

    /// Milliseconds since the start (server time), nil before the battle has a start.
    var elapsedMs: Int64? { startMs.map { serverNowMs - $0 } }

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
        case "best_of_3":
            // Over after round 3, or right after round 2 when I've certainly won the first two.
            if t >= BattleHud.bo3EndMs { return true }
            return t >= 2 * BattleHud.roundMs - BattleHud.restMs
                && BattleHud.bo3Clinched(mySets: BattleHud.mySets(myReps), theirRaw: battle.theirRounds)
        case "turns":
            // Someone missed the 5 s window (a little grace for the opponent's polled time), or the 200-rep cap.
            if myReps.count + battle.theirScore >= 200 { return true }
            guard let state = turn(t), let left = state.msLeft else { return t >= 20 * 60_000 }
            return state.turn == "me" ? left < -500 : left < -1500
        default:
            return t >= 360_000
        }
    }

    /// The scores that decide the battle right now (D-066 lead bar + announcer): the current round in Best of 3,
    /// nothing in Turns (it alternates), else all reps.
    public var lead: (mine: Int, theirs: Int)? {
        switch mode {
        case "turns": return nil
        case "best_of_3":
            guard let t = elapsedMs else { return nil }
            let r = BattleHud.bo3Clock(t).round
            let theirs = battle.theirRounds
            return (myReps.filter { $0.round == r }.count, r < theirs.count ? theirs[r] : 0)
        default:
            return (myReps.count, battle.theirScore)
        }
    }

    private func handle(_ callouts: [BattleCallout]) {
        for c in callouts {
            switch c {
            case .countdown: sounds.play(.count)
            case .go: sounds.play(.go)
            case .opponentRep: sounds.play(.opponent)
            case .tookLead: sounds.play(.lead)
            case .lostLead, .behind: sounds.play(.behind)
            case .tied, .secondsLeft: break
            }
            guard let text = BattleAnnouncer.text(c) else { continue }
            sounds.announce(text)
            if case .countdown = c { continue }
            let positive = switch c {
            case .lostLead, .behind: false
            default: true
            }
            callout = (text, positive, (callout?.id ?? 0) + 1)
        }
    }

    /// Turns: a rep that came after the opponent's (now known) last rep was a valid turn after all.
    func promoteTurnReps() {
        guard mode == "turns", !unconfirmed.isEmpty, let theirs = battle.theirLastRepT else { return }
        let mine = myReps.last?.t ?? Int64.min
        if let rep = unconfirmed.first(where: { $0.t > theirs && $0.t > mine }) {
            myReps.append(rep)
        }
        unconfirmed.removeAll { $0.t <= theirs || $0.t <= (myReps.last?.t ?? Int64.min) }
    }

    /// Turns mode: whose turn it is now.
    func turn(_ t: Int64) -> BattleHud.TurnState? {
        guard mode == "turns" else { return nil }
        return BattleHud.turnState(t: t, myLast: myReps.last?.t, theirLast: battle.theirLastRepT)
    }

    /// Best of 3: my set in the current round has ended (pause > 2 s) — more reps don't count until the next round.
    var bo3SetOver: Bool {
        guard mode == "best_of_3", let t = elapsedMs else { return false }
        let clock = BattleHud.bo3Clock(t)
        guard clock.phase == "set", let last = myReps.last(where: { $0.round == clock.round }) else { return false }
        return t - last.t > BattleHud.setGapMs
    }

    private func counted(_ total: Int) {
        guard phase == .live, let start = startMs else { return }
        let t = serverNowMs - start
        var round = 0
        if mode == "best_of_3" {
            let clock = BattleHud.bo3Clock(t)
            // Reps during the rest or after the set ended don't count (the server drops / ignores them too).
            guard clock.phase == "set", !bo3SetOver else { return }
            round = clock.round
        }
        let rep = BattleRules.Rep(t: t, q: reps.lastQuality ?? 0, round: round)
        pending.append(PushRep(round: round, i: total, t: rep.t, q: rep.q))
        if mode == "turns", turn(t)?.turn == "them" {
            // Looks like their turn, but their last rep time is polled (≤ 1 s old): keep it until the next poll.
            unconfirmed.append(rep)
            return
        }
        myReps.append(rep)
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
