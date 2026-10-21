package app.pushly.feature.battle

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.pushly.core.common.BattleService
import app.pushly.core.common.PLog
import app.pushly.engine.rep.RepState
import app.pushly.feature.wakeflow.RepSessionModel
import app.pushly.feature.wakeflow.ServerAnchor
import app.pushly.feature.wakeflow.SessionServices
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import java.time.Instant
import java.util.UUID
import java.util.concurrent.ConcurrentLinkedQueue

/** Battle tab hub (doc 07 §3, §8): quick match queue, friend invites, history. Same behaviour as iOS BattleHubModel. */
class BattleHubViewModel(
    private val service: BattleService,
    private val friendsJson: (suspend () -> String)?,
) : ViewModel() {
    enum class Notice { None, QueueFailed, NobodyFound, ChallengeSent, ChallengeFailed, Expired }

    data class UiState(
        val invites: BattleInvites = BattleInvites(),
        val history: List<Battle> = emptyList(),
        val friends: List<FriendPick> = emptyList(),
        val queuedMode: BattleMode? = null,
        val waitedS: Int = 0,
        val notice: Notice = Notice.None,
        val noticeName: String = "",
        /** Set when a battle is ready to play — the screen opens it. */
        val active: Battle? = null,
    )

    private val _state = MutableStateFlow(UiState())
    val state: StateFlow<UiState> = _state.asStateFlow()
    private var poller: Job? = null

    fun load() {
        viewModelScope.launch {
            runCatching { BattleInvites.decode(service.battleInvites()) }.onSuccess { inv -> _state.update { it.copy(invites = inv) } }
            runCatching { Battle.decodeList(service.battleHistory()) }.onSuccess { h -> _state.update { it.copy(history = h) } }
            friendsJson?.let { f ->
                runCatching { BattleJson.decodeFromString(FriendsPayload.serializer(), f()).friends }
                    .onSuccess { list -> _state.update { it.copy(friends = list) } }
            }
        }
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
                    _state.update { it.copy(queuedMode = mode, waitedS = 0, notice = Notice.None) }
                    pollQueue()
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.update { it.copy(notice = Notice.QueueFailed) }
            }
        }
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
                        _state.update { it.copy(queuedMode = null, notice = Notice.NobodyFound) }
                        return@launch
                    }
                    else -> _state.update { it.copy(waitedS = status.waitedS ?: (it.waitedS + 2)) }
                }
            }
        }
    }

    fun challenge(friend: FriendPick, mode: BattleMode, ranked: Boolean) {
        viewModelScope.launch {
            try {
                service.createBattleInvite(friend.id, mode.wire, ranked)
                _state.update { it.copy(notice = Notice.ChallengeSent, noticeName = friend.username) }
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
    )

    @Serializable private data class PushRep(val round: Int, val i: Int, val t: Long, val q: Int)

    val reps = RepSessionModel(RepSessionModel.Mode.Open)
    private val _state = MutableStateFlow(UiState(initial))
    val state: StateFlow<UiState> = _state.asStateFlow()

    private val myReps = ConcurrentLinkedQueue<BattleRules.Rep>()
    private val pending = ConcurrentLinkedQueue<PushRep>()
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
            runCatching { Battle.decode(service.battle(battle.id)) }.onSuccess { fresh -> _state.update { it.copy(battle = fresh) } }
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
            _state.update { it.copy(phase = Phase.Countdown(((-t + 999) / 1000).toInt())) }
            return
        }
        if (phase != Phase.Live) {
            reps.restartClock()
            _state.update { it.copy(phase = Phase.Live) }
        }
        _state.update { it.copy(secondsLeft = remainingSeconds(t), myCount = myReps.size) }
        if (shouldEnd(t)) finish() else flush()
    }

    private fun remainingSeconds(t: Long): Int? = when (battle.mode) {
        "max_reps" -> (maxOf(0, (battle.variant["durationS"] ?: 60) * 1000L - t) / 1000).toInt()
        "speed" -> (maxOf(0, 120_000 - t) / 1000).toInt()
        else -> null
    }

    private fun shouldEnd(t: Long): Boolean = when (battle.mode) {
        "max_reps" -> t >= (battle.variant["durationS"] ?: 60) * 1000L
        "speed" -> {
            val target = battle.variant["targetReps"] ?: 20
            myReps.size >= target || battle.theirScore >= target || t >= 120_000
        }
        "endurance" -> myReps.lastOrNull()?.let { t - it.t > 3000 } ?: (t >= 600_000)
        else -> t >= 360_000
    }

    /** Camera thread: queue the rep in server time. */
    private fun counted(total: Int) {
        if (_state.value.phase != Phase.Live) return
        val start = startMs ?: return
        val rep = BattleRules.Rep(serverNowMs - start, reps.state.value.lastQuality ?: 0)
        myReps += rep
        pending += PushRep(0, total, rep.t, rep.q)
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
