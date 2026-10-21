package app.pushly.feature.clan

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.pushly.core.common.ClanService
import app.pushly.core.common.PLog
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** Clan tab state (doc 09 §4–5). Same behaviour as iOS ClanModel. */
class ClanViewModel(private val service: ClanService) : ViewModel() {
    enum class Notice { None, Requested, Taken, InvalidName, InvalidTag, Full, Requirements, AlreadyInClan, RateLimited, Failed }

    data class UiState(
        val home: ClanHome? = null,
        val loaded: Boolean = false,
        val failed: Boolean = false,
        val query: String = "",
        val results: List<ClanSummary> = emptyList(),
        val messages: List<ClanMessage> = emptyList(),
        val notice: Notice = Notice.None,
        val busy: Boolean = false,
    ) {
        val myRole: ClanRole? get() = ClanRole.of(home?.summary?.myRole)
    }

    private val _state = MutableStateFlow(UiState())
    val state: StateFlow<UiState> = _state.asStateFlow()

    private fun go(block: suspend () -> Unit) {
        viewModelScope.launch { block() }
    }

    fun start() = go { load() }
    fun setQuery(q: String) {
        _state.update { it.copy(query = q) }
        go { search() }
    }
    fun join(c: ClanSummary) = go { join(c.id) }
    fun respond(userId: String, accept: Boolean) = go { act { service.respondClanRequest(userId, accept) } }
    fun leave() = go { act { service.leaveClan() } }
    fun kick(userId: String) = go { act { service.kickMember(userId) } }
    fun setRole(userId: String, role: ClanRole) = go { act { service.setMemberRole(userId, role.wire) } }
    fun transfer(userId: String) = go { act { service.transferLeadership(userId) } }
    fun create(name: String, tag: String, about: String, policy: String, onDone: () -> Unit) = go {
        if (create(name, tag, about, policy)) onDone()
    }
    fun send(body: String, kind: String = "text", onSent: () -> Unit = {}) = go { if (sendNow(body, kind)) onSent() }
    fun refreshMessages() = go { loadMessages() }

    suspend fun load() {
        try {
            val home = ClanHome.decode(service.myClan())
            _state.update { it.copy(home = home, failed = false, loaded = true) }
            if (home == null && _state.value.results.isEmpty()) search()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            PLog.error { "clan load failed: ${e.message}" }
            _state.update { it.copy(failed = !it.loaded, loaded = true) }
        }
    }

    suspend fun search() {
        val q = _state.value.query.trim()
        try {
            val found = ClanSummary.decodeList(service.searchClans(q))
            if (_state.value.query.trim() == q) _state.update { it.copy(results = found) }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            PLog.error { "clan search failed: ${e.message}" }
        }
    }

    suspend fun create(name: String, tag: String, about: String, policy: String): Boolean {
        _state.update { it.copy(busy = true) }
        return try {
            service.createClan(name.trim(), tag.trim().uppercase(), about, policy)
            _state.update { it.copy(notice = Notice.None, busy = false) }
            load()
            true
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            _state.update { it.copy(notice = noticeFor(e), busy = false) }
            false
        }
    }

    suspend fun join(clanId: String) {
        act {
            val outcome = service.joinClan(clanId, null)
            if (outcome == "requested") _state.update { it.copy(notice = Notice.Requested) }
        }
        search()
    }

    suspend fun loadMessages() {
        try {
            val msgs = ClanMessage.decodeList(service.clanMessages(null))
            _state.update { it.copy(messages = msgs) }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            PLog.error { "clan chat failed: ${e.message}" }
        }
    }

    suspend fun sendNow(body: String, kind: String): Boolean {
        val text = body.trim()
        if (text.isEmpty()) return false
        return try {
            service.sendClanMessage(text, kind)
            _state.update { it.copy(notice = Notice.None) }
            loadMessages()
            true
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            _state.update { it.copy(notice = noticeFor(e)) }
            false
        }
    }

    private suspend fun act(body: suspend () -> Unit) {
        _state.update { it.copy(busy = true, notice = Notice.None) }
        try {
            body()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            _state.update { it.copy(notice = noticeFor(e)) }
        }
        _state.update { it.copy(busy = false) }
        load()
    }

    companion object {
        /** Server hints → notices. */
        fun noticeFor(e: Exception): Notice {
            val t = "${e.message} ${e.cause?.message}"
            return when {
                "rate_limited" in t || "rate limited" in t -> Notice.RateLimited
                "taken" in t -> Notice.Taken
                "invalid_name" in t -> Notice.InvalidName
                "invalid_tag" in t -> Notice.InvalidTag
                "full" in t -> Notice.Full
                "requirements" in t -> Notice.Requirements
                "already_in_clan" in t -> Notice.AlreadyInClan
                else -> Notice.Failed
            }
        }
    }
}
