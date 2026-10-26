package app.pushly.feature.battle

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.pushly.core.common.BattleService
import app.pushly.core.common.PLog
import app.pushly.core.common.PushPrompt
import app.pushly.engine.rep.RepState
import app.pushly.feature.wakeflow.RepSessionModel
import app.pushly.feature.wakeflow.ServerAnchor
import app.pushly.feature.wakeflow.SessionServices
import java.time.Instant
import java.util.UUID
import java.util.concurrent.ConcurrentLinkedQueue
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer

/** Battle tab hub (doc 07 §3, §8): quick match queue, friend invites, history. Same behaviour as iOS BattleHubModel. */
class BattleHubViewModel(
    private val service: BattleService,
    private val friendsJson: (suspend () -> String)?,
    /** `get_battle_stats()` JSON for the arena header (D-071). */
    private val statsJson: (suspend () -> String)? = null,
    /** `search_users(q)` JSON — add friends from the Friends sheet (D-072). */
    private val searchUsersJson: (suspend (String) -> String)? = null,
    /** `send_friend_request(user_id)`. */
    private val sendFriendRequest: (suspend (String) -> Unit)? = null,
    /** `get_leaderboard('battles', scope, 'season')` JSON — the trophy board (D-075). */
    private val trophyBoardJson: (suspend (String) -> String)? = null,
    /** `get_clan_leaderboard('rating')` JSON. */
    private val clanBoardJson: (suspend () -> String)? = null,
) : ViewModel() {
    enum class Notice {
        None, QueueFailed, NobodyFound, ChallengeSent, ChallengeFailed, Expired, GhostLimit, NoGhost, BotFailed, FriendRequested,
        FriendRequestFailed,
    }

    data class UiState(
        val invites: BattleInvites = BattleInvites(),
        val history: List<Battle> = emptyList(),
        val friends: List<FriendPick> = emptyList(),
        val seasons: List<SeasonResult> = emptyList(),
        val queuedMode: BattleMode? = null,
        val waitedS: Int = 0,
        val notice: Notice = Notice.None,
        val noticeName: String = "",
        /** Offered when nobody is in the queue: practise against a bot in this mode instead (D-063). */
        val botOffer: BattleMode? = null,
        /** Set when a battle is ready to play — the screen opens it. */
        val active: Battle? = null,
        /** Trophies, league, rank and record for the arena header (null until loaded / offline). */
        val arena: ArenaStatus? = null,
        /** Username search results in the Friends sheet. */
        val userHits: List<UserHit> = emptyList(),
        /** Leaderboard sheet (D-075). */
        val trophyBoard: TrophyBoard? = null,
        val clanBoard: List<ClanBoardRow> = emptyList(),
        val boardFailed: Boolean = false,
    )

    companion object {
        /** Seconds in the queue before a ranked Arena Bot steps in (D-075; the server allows it from 9 s). */
        const val ARENA_BOT_AFTER_S = 10
    }

    private var queuedAtMs = 0L

    private val _state = MutableStateFlow(UiState())
    val state: StateFlow<UiState> = _state.asStateFlow()
    private var poller: Job? = null

    fun load() {
        viewModelScope.launch {
            runCatching { BattleInvites.decode(service.battleInvites()) }.onSuccess { inv -> _state.update { it.copy(invites = inv) } }
            runCatching { Battle.decodeList(service.battleHistory()) }.onSuccess { h -> _state.update { it.copy(history = h) } }
            runCatching { SeasonResult.decodeList(service.seasonHistory()) }.onSuccess { list -> _state.update { it.copy(seasons = list) } }
            statsJson?.let { f ->
                runCatching { ArenaStatus.decode(f()) }.onSuccess { a -> _state.update { it.copy(arena = a) } }
            }
            friendsJson?.let { f ->
                runCatching { BattleJson.decodeFromString(FriendsPayload.serializer(), f()).friends }
                    .onSuccess { list -> _state.update { it.copy(friends = list) } }
            }
        }
    }

    private var searchJob: Job? = null

    /** Username search (≥ 2 letters), debounced 300 ms; stale answers are dropped. */
    fun searchUsers(query: String) {
        searchJob?.cancel()
        val q = query.trim()
        if (q.length < 2) {
            _state.update { it.copy(userHits = emptyList()) }
            return
        }
        val search = searchUsersJson ?: return
        searchJob = viewModelScope.launch {
            delay(300)
            runCatching { UserHit.decodeList(search(q)) }.onSuccess { hits -> _state.update { it.copy(userHits = hits) } }
        }
    }

    fun addFriend(user: UserHit) {
        val send = sendFriendRequest ?: return
        viewModelScope.launch {
            try {
                send(user.id)
                _state.update { s ->
                    s.copy(userHits = s.userHits.map { if (it.id == user.id) it.copy(relation = "outgoing") else it },
                        notice = Notice.FriendRequested, noticeName = user.username)
                }
                PushPrompt.request(PushPrompt.Reason.Friends)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.update { it.copy(notice = Notice.FriendRequestFailed) }
            }
        }
    }

    fun loadTrophyBoard(scope: String) {
        val f = trophyBoardJson ?: return
        viewModelScope.launch {
            runCatching { TrophyBoard.decode(f(scope)) }
                .onSuccess { b -> _state.update { it.copy(trophyBoard = b, boardFailed = false) } }
                .onFailure { e -> if (e is CancellationException) throw e else _state.update { it.copy(boardFailed = true) } }
        }
    }

    fun loadClanBoard() {
        val f = clanBoardJson ?: return
        viewModelScope.launch {
            runCatching { ClanBoardRow.decodeBoard(f()) }
                .onSuccess { rows -> _state.update { it.copy(clanBoard = rows, boardFailed = false) } }
                .onFailure { e -> if (e is CancellationException) throw e else _state.update { it.copy(boardFailed = true) } }
        }
    }

    fun clearNotice() {
        _state.update { it.copy(notice = Notice.None) }
    }

    fun closeBattle() {
        _state.update { it.copy(active = null) }
        load()
    }

    fun quickMatch(mode: BattleMode) {
        viewModelScope.launch {
            try {
                val status = MatchmakingStatus.decode(service.matchmakingJoin(mode.wire))
                val battle = status.battle
                if (battle != null) {
                    _state.update { it.copy(active = battle) }
                } else {
                    _state.update { it.copy(queuedMode = mode, waitedS = 0, notice = Notice.None, botOffer = null) }
                    queuedAtMs = System.currentTimeMillis()
                    pollQueue()
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.update { it.copy(notice = Notice.QueueFailed) }
            }
        }
    }

    /** Ghost battle (doc 07 §7): starts at once against a recorded run of a similar player. */
    fun ghost(mode: BattleMode) {
        viewModelScope.launch {
            try {
                val battle = Battle.decode(service.startGhostBattle(mode.wire))
                _state.update { it.copy(active = battle, notice = Notice.None) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                val limit = "${e.message}".contains("limit")
                _state.update { it.copy(notice = if (limit) Notice.GhostLimit else Notice.NoGhost) }
            }
        }
    }

    /** Practice against a labelled bot (D-063): no trophies, starts at once. */
    fun practice(mode: BattleMode, level: BotLevel?) {
        viewModelScope.launch {
            _state.update { it.copy(botOffer = null) }
            try {
                val battle = Battle.decode(service.startBotBattle(mode.wire, level?.wire))
                _state.update { it.copy(active = battle, notice = Notice.None) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.update { it.copy(notice = Notice.BotFailed) }
            }
        }
    }

    /** Leaves the queue and fights a bot in the same mode instead. */
    fun practiceInsteadOfWaiting() {
        val mode = _state.value.queuedMode ?: _state.value.botOffer ?: return
        cancelQueue()
        practice(mode, null)
    }

    fun cancelQueue() {
        poller?.cancel()
        _state.update { it.copy(queuedMode = null) }
        viewModelScope.launch { runCatching { service.matchmakingLeave() } }
    }

    private fun pollQueue() {
        poller?.cancel()
        poller = viewModelScope.launch {
            while (_state.value.queuedMode != null) {
                delay(2000)
                val status = runCatching { MatchmakingStatus.decode(service.matchmakingStatus()) }.getOrNull() ?: continue
                val battle = status.battle
                when {
                    battle != null -> {
                        _state.update { it.copy(queuedMode = null, active = battle) }
                        return@launch
                    }
                    !status.queued -> {
                        _state.update { it.copy(queuedMode = null, notice = Notice.NobodyFound, botOffer = it.queuedMode) }
                        return@launch
                    }
                    else -> {
                        _state.update { it.copy(waitedS = status.waitedS ?: (it.waitedS + 2)) }
                        val mode = _state.value.queuedMode
                        if (mode != null && mode.quickMatch && System.currentTimeMillis() - queuedAtMs >= ARENA_BOT_AFTER_S * 1000L) {
                            // nobody near your trophies right now: a ranked Arena Bot at your level (D-075)
                            val bot = runCatching { Battle.decode(service.matchmakingBot()) }.getOrNull()
                            if (bot != null) {
                                _state.update { it.copy(queuedMode = null, active = bot) }
                                return@launch
                            }
                        }
                    }
                }
            }
        }
    }

    /** Rematch (doc 08 §5): friend battles — same mode, as a new (friendly) challenge; bots — same level. */
    fun rematch(battle: Battle) {
        _state.update { it.copy(active = null) }
        if (battle.bot == "arena") {
            BattleMode.of(battle.mode)?.let { quickMatch(it) }
            return
        }
        if (battle.bot != null) {
            BattleMode.of(battle.mode)?.let { practice(it, BotLevel.of(battle.bot)) }
            return
        }
        val id = battle.opponent.id ?: return
        val mode = BattleMode.of(battle.mode) ?: return
        if (battle.type !in setOf("friendly", "friend_ranked")) return
        challenge(FriendPick(id, battle.opponent.username, battle.opponent.avatarPreset), mode)
    }

    /** Friend battles are always friendly — no trophies (D-071). */
    fun challenge(friend: FriendPick, mode: BattleMode) {
        viewModelScope.launch {
            try {
                service.createBattleInvite(friend.id, mode.wire, false)
                _state.update { it.copy(notice = Notice.ChallengeSent, noticeName = friend.username) }
                PushPrompt.request(PushPrompt.Reason.Battles)
                watchOutgoing()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.update { it.copy(notice = Notice.ChallengeFailed) }
            }
        }
    }

    /** Waits for an accepted outgoing invite, then opens the battle. */
    private fun watchOutgoing() {
        poller?.cancel()
        poller = viewModelScope.launch {
            repeat(100) {
                delay(3000)
                val inv = runCatching { BattleInvites.decode(service.battleInvites()) }.getOrNull() ?: return@repeat
                _state.update { it.copy(invites = inv) }
                val id = inv.outgoing.firstOrNull { it.status == "accepted" && it.battleId != null }?.battleId ?: return@repeat
                val battle = runCatching { Battle.decode(service.battle(id)) }.getOrNull()
                if (battle != null && !battle.isOver) {
                    _state.update { it.copy(active = battle) }
                    return@launch
                }
            }
        }
    }

    fun accept(invite: BattleInvites.Incoming) {
        viewModelScope.launch {
            try {
                val battle = Battle.decode(service.respondBattleInvite(invite.id, true))
                _state.update { it.copy(active = battle) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.update { it.copy(notice = Notice.Expired) }
            }
            load()
        }
    }

    fun decline(invite: BattleInvites.Incoming) {
        viewModelScope.launch {
            runCatching { service.respondBattleInvite(invite.id, false) }
            load()
        }
    }
}

/**
 * One live battle (doc 07 §4): ready check → server countdown → live counting with rep events in server time →
 * finish (rep log + battle_finish) → settled result. Opponent score from polling `get_battle` once a second.
 * Same behaviour as iOS LiveBattleModel.
 */
class LiveBattleViewModel(
    initial: Battle,
    private val service: BattleService,
    private val sessions: SessionServices?,
) : ViewModel() {
    sealed interface Phase {
        data object Lobby : Phase
        data class Countdown(val seconds: Int) : Phase
        data object Live : Phase
        data object Waiting : Phase
        data object Done : Phase
        data object Cancelled : Phase
    }

    data class UiState(
        val battle: Battle,
        val phase: Phase = Phase.Lobby,
        val myCount: Int = 0,
        val secondsLeft: Int? = null,
        /** ms since the start at the last tick (drives the Best of 3 / Turns HUD). */
        val elapsedMs: Long? = null,
        /** Scores that decide the battle right now (lead bar, D-066); null in Turns. */
        val lead: Pair<Int, Int>? = null,
    )

    @Serializable private data class PushRep(val round: Int, val i: Int, val t: Long, val q: Int)

    val reps = RepSessionModel(RepSessionModel.Mode.Open, allowFront = false)
    private val _state = MutableStateFlow(UiState(initial))
    val state: StateFlow<UiState> = _state.asStateFlow()
    private val announcer = BattleAnnouncer()
    private val _callouts = MutableSharedFlow<BattleCallout>(extraBufferCapacity = 16)

    /** Announcer events (D-066): the screen plays the sound, speaks the line and flashes it. */
    val callouts: SharedFlow<BattleCallout> = _callouts.asSharedFlow()

    private val myReps = ConcurrentLinkedQueue<BattleRules.Rep>()
    private val pending = ConcurrentLinkedQueue<PushRep>()
    private val unconfirmed = ConcurrentLinkedQueue<BattleRules.Rep>()
    private var anchor: ServerAnchor? = null
    private var readySent = false
    private var finished = false
    private var lastPoll = 0L
    private var ticker: Job? = null
    private val sessionId = UUID.randomUUID().toString()

    private val battle: Battle get() = _state.value.battle

    init {
        reps.onCounted = { total -> counted(total) }
    }

    /** Server time now (anchor + monotonic), else the phone clock. */
    private val serverNowMs: Long
        get() = anchor?.let { it.serverMs + (reps.monotonicNowMs - it.monotonicMs) } ?: reps.nowMs

    private val startMs: Long?
        get() = battle.startAt?.let { runCatching { Instant.parse(it).toEpochMilli() }.getOrNull() }

    /** Split-screen video with the opponent (doc 07 §5); people only — no video against ghosts and bots. */
    fun startVideo(video: BattleVideo) {
        val battle = _state.value.battle
        if (battle.ghost == true) return
        viewModelScope.launch { video.start(battle.id, service, reps, viewModelScope) }
    }

    fun start() {
        if (ticker != null) return
        ticker = viewModelScope.launch {
            anchor = sessions?.anchor()
            while (true) {
                tick()
                if (_state.value.phase is Phase.Done || _state.value.phase is Phase.Cancelled) break
                delay(250)
            }
        }
    }

    private suspend fun tick() {
        val now = serverNowMs
        if (now - lastPoll >= 1000) {
            lastPoll = now
            runCatching { Battle.decode(service.battle(battle.id)) }.onSuccess { fresh ->
                _state.update { it.copy(battle = fresh) }
                promoteTurnReps()
            }
        }
        when (battle.status) {
            "cancelled", "void" -> return _state.update { it.copy(phase = Phase.Cancelled) }
            "settled" -> return _state.update { it.copy(phase = Phase.Done) }
        }
        val phase = _state.value.phase
        if (phase == Phase.Waiting || phase == Phase.Done) return
        if (!readySent && reps.state.value.repState != RepState.NotReady && battle.status in setOf("lobby", "ready_check")) {
            readySent = true
            runCatching { Battle.decode(service.battleReady(battle.id)) }.onSuccess { b -> _state.update { it.copy(battle = b) } }
        }
        val start = startMs ?: return
        val t = now - start
        if (t < 0) {
            val n = ((-t + 999) / 1000).toInt()
            _state.update { it.copy(phase = Phase.Countdown(n)) }
            announcer.countdown(n).forEach { _callouts.tryEmit(it) }
            return
        }
        if (phase != Phase.Live) {
            reps.restartClock()
            _state.update { it.copy(phase = Phase.Live) }
        }
        val lead = lead(t)
        val secondsLeft = remainingSeconds(t)
        _state.update { it.copy(secondsLeft = secondsLeft, myCount = myReps.size, elapsedMs = t, lead = lead) }
        announcer.live(lead?.first, lead?.second, battle.theirScore, secondsLeft, reps.monotonicNowMs)
            .forEach { _callouts.tryEmit(it) }
        if (shouldEnd(t)) finish() else flush()
    }

    /** The current round in Best of 3, nothing in Turns (it alternates), else all reps. */
    private fun lead(t: Long): Pair<Int, Int>? = when (battle.mode) {
        "turns" -> null
        "best_of_3" -> {
            val r = BattleHud.bo3Clock(t).round
            val theirs = battle.theirRounds
            myReps.count { it.round == r } to (theirs.getOrNull(r) ?: 0)
        }
        else -> myReps.size to battle.theirScore
    }

    private fun remainingSeconds(t: Long): Int? = when (battle.mode) {
        "max_reps" -> (maxOf(0, (battle.variant["durationS"] ?: 60) * 1000L - t) / 1000).toInt()
        "speed" -> (maxOf(0, 120_000 - t) / 1000).toInt()
        "best_of_3" -> ((BattleHud.bo3Clock(t).msLeft + 999) / 1000).toInt()
        else -> null
    }

    /** Milliseconds since the start (server time), null before the battle has a start. */
    val elapsedMs: Long? get() = startMs?.let { serverNowMs - it }

    private fun shouldEnd(t: Long): Boolean = when (battle.mode) {
        "max_reps" -> t >= (battle.variant["durationS"] ?: 60) * 1000L
        "speed" -> {
            val target = battle.variant["targetReps"] ?: 20
            myReps.size >= target || battle.theirScore >= target || t >= 120_000
        }
        "endurance" -> myReps.lastOrNull()?.let { t - it.t > 3000 } ?: (t >= 600_000)
        // Over after round 3, or right after round 2 when I've certainly won the first two.
        "best_of_3" -> t >= BattleHud.BO3_END_MS ||
            (t >= 2 * BattleHud.ROUND_MS - BattleHud.REST_MS && BattleHud.bo3Clinched(BattleHud.mySets(myReps.toList()), battle.theirRounds))
        // Someone missed the 5 s window (a little grace for the opponent's polled time), or the 200-rep cap.
        "turns" -> {
            val state = turn(t)
            val left = state?.msLeft
            when {
                myReps.size + battle.theirScore >= 200 -> true
                state == null || left == null -> t >= 20 * 60_000L
                state.turn == "me" -> left < -500
                else -> left < -1500
            }
        }
        else -> t >= 360_000
    }

    /** Turns mode: whose turn it is now. */
    fun turn(t: Long): BattleHud.TurnState? =
        if (battle.mode != "turns") null else BattleHud.turnState(t, myReps.lastOrNull()?.t, battle.theirLastRepT)

    /** Best of 3: my set in the current round has ended (pause > 2 s) — more reps don't count until the next round. */
    val bo3SetOver: Boolean
        get() {
            val t = elapsedMs ?: return false
            if (battle.mode != "best_of_3") return false
            val clock = BattleHud.bo3Clock(t)
            if (clock.phase != "set") return false
            val last = myReps.lastOrNull { it.round == clock.round } ?: return false
            return t - last.t > BattleHud.SET_GAP_MS
        }

    fun myRepsSnapshot(): List<BattleRules.Rep> = myReps.toList()

    /** Turns: a rep that came after the opponent's (now known) last rep was a valid turn after all. */
    private fun promoteTurnReps() {
        if (battle.mode != "turns" || unconfirmed.isEmpty()) return
        val theirs = battle.theirLastRepT ?: return
        val mine = myReps.lastOrNull()?.t ?: Long.MIN_VALUE
        unconfirmed.firstOrNull { it.t > theirs && it.t > mine }?.let { myReps += it }
        val newest = myReps.lastOrNull()?.t ?: Long.MIN_VALUE
        unconfirmed.removeAll { it.t <= theirs || it.t <= newest }
    }

    /** Camera thread: queue the rep in server time. */
    private fun counted(total: Int) {
        if (_state.value.phase != Phase.Live) return
        val start = startMs ?: return
        val t = serverNowMs - start
        var round = 0
        if (battle.mode == "best_of_3") {
            val clock = BattleHud.bo3Clock(t)
            // Reps during the rest or after the set ended don't count (the server drops / ignores them too).
            if (clock.phase != "set" || bo3SetOver) return
            round = clock.round
        }
        val rep = BattleRules.Rep(t, reps.state.value.lastQuality ?: 0, round)
        pending += PushRep(round, total, rep.t, rep.q)
        if (battle.mode == "turns" && turn(t)?.turn == "them") {
            // Looks like their turn, but their last rep time is polled (≤ 1 s old): keep it until the next poll.
            unconfirmed += rep
            return
        }
        myReps += rep
    }

    private suspend fun flush() {
        if (pending.isEmpty()) return
        val batch = generateSequence { pending.poll() }.toList()
        try {
            service.battlePushReps(battle.id, BattleJson.encodeToString(ListSerializer(PushRep.serializer()), batch))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            PLog.warning { "battle push failed, retrying: ${e.message}" }
            pending.addAll(batch)
        }
    }

    private suspend fun finish() {
        if (finished) return
        finished = true
        _state.update { it.copy(phase = Phase.Waiting) }
        reps.finish("completed")
        flush()
        sessions?.let { s ->
            s.uploader.enqueue(reps.repLog(sessionId, "battle", s.appVersion, anchor = anchor, battleId = battle.id))
        }
        runCatching { Battle.decode(service.battleFinish(battle.id)) }.onSuccess { b ->
            _state.update { it.copy(battle = b, phase = if (b.status == "settled") Phase.Done else Phase.Waiting) }
        }
    }

    fun leave() {
        viewModelScope.launch {
            reps.finish("gaveUp")
            runCatching { Battle.decode(service.battleForfeit(battle.id)) }.onSuccess { b -> _state.update { it.copy(battle = b) } }
            _state.update { it.copy(phase = if (battle.status == "cancelled") Phase.Cancelled else Phase.Done) }
            ticker?.cancel()
        }
    }

    /** Provisional result until the server settles (same rules as the server). */
    fun provisional(): BattleRules.Result {
        val mine = myReps.toList()
        return if (battle.me == "a") {
            BattleRules.decide(battle.mode, battle.variant, mine, emptyList())
        } else {
            BattleRules.decide(battle.mode, battle.variant, emptyList(), mine)
        }
    }
}
