package app.pushly.feature.social

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.pushly.core.common.PLog
import app.pushly.core.common.PushPrompt
import app.pushly.core.common.SocialService
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** Friends screen (doc 15 §1): lists, requests, search, feed and kudos. Same behaviour as iOS FriendsModel. */
class FriendsViewModel(private val service: SocialService) : ViewModel() {
    enum class Notice { None, RequestSent, Failed }

    data class UiState(
        val list: FriendsList = FriendsList(),
        val feed: List<FeedItem> = emptyList(),
        val query: String = "",
        val results: List<UserCard> = emptyList(),
        val loaded: Boolean = false,
        val failed: Boolean = false,
        val notice: Notice = Notice.None,
        val noticeName: String = "",
    )

    private val _state = MutableStateFlow(UiState())
    val state: StateFlow<UiState> = _state.asStateFlow()

    fun start() = launch { if (!_state.value.loaded) load() }
    fun setQuery(q: String) {
        _state.update { it.copy(query = q) }
        launch { search() }
    }
    fun add(user: UserCard) = launch { add(user.id, user.username) }
    fun respond(user: UserCard, accept: Boolean) = launch { act { service.respondFriendRequest(user.id, accept) } }
    fun remove(userId: String) = launch { act { service.removeFriend(userId) } }
    fun block(userId: String) = launch { act { service.blockUser(userId) } }
    fun unblock(userId: String) = launch { act { service.unblockUser(userId) } }
    fun giveKudos(item: FeedItem) = launch { kudos(item) }
    fun refresh() = launch { load() }

    /** One refresh, awaited — the screens poll this while open (D-078). */
    suspend fun reload() = load()

    private fun launch(block: suspend () -> Unit) {
        viewModelScope.launch { block() }
    }

    suspend fun load() {
        try {
            coroutineScope {
                val friends = async { FriendsList.decode(service.listFriends()) }
                val feed = async { FeedItem.decodeList(service.friendFeed()) }
                val f = friends.await()
                val e = feed.await()
                _state.update { it.copy(list = f, feed = e, failed = false, loaded = true) }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            PLog.error { "friends load failed: ${e.message}" }
            _state.update { it.copy(failed = !it.loaded, loaded = true) }
        }
    }

    suspend fun search() {
        val q = _state.value.query.trim()
        if (q.length < 2) {
            _state.update { it.copy(results = emptyList()) }
            return
        }
        try {
            val found = UserCard.decodeList(service.searchUsers(q))
            if (_state.value.query.trim() == q) _state.update { it.copy(results = found) }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            PLog.error { "search failed: ${e.message}" }
        }
    }

    suspend fun add(userId: String, username: String) {
        act { service.sendFriendRequest(userId) }
        if (_state.value.notice != Notice.Failed) {
            _state.update { it.copy(notice = Notice.RequestSent, noticeName = username) }
            PushPrompt.request(PushPrompt.Reason.Friends)
        }
        search()
    }

    /** One 👊 per event; optimistic, rolled back if the server refuses. */
    suspend fun kudos(item: FeedItem) {
        if (item.kudosByMe) return
        fun patch(id: Long, f: (FeedItem) -> FeedItem) =
            _state.update { s -> s.copy(feed = s.feed.map { if (it.id == id) f(it) else it }) }
        patch(item.id) { it.copy(kudosByMe = true, kudos = it.kudos + 1) }
        try {
            val count = service.giveKudos(item.id)
            patch(item.id) { it.copy(kudos = count) }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            patch(item.id) { it.copy(kudosByMe = false, kudos = it.kudos - 1) }
        }
    }

    private suspend fun act(body: suspend () -> Unit) {
        try {
            body()
            _state.update { it.copy(notice = Notice.None) }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            PLog.error { "friends action failed: ${e.message}" }
            _state.update { it.copy(notice = Notice.Failed) }
        }
        load()
    }
}

/** Ranks tab (doc 08 §4, PS-60…PS-63). Answers are cached for 60 s per board / scope / period. Same as iOS. */
class RanksViewModel(private val service: SocialService, private val now: () -> Long = System::currentTimeMillis) : ViewModel() {
    data class UiState(
        val board: Board = Board.Wake,
        val scope: String = "global",
        val period: String = "week",
        val boards: Map<String, Leaderboard> = emptyMap(),
        val loading: Boolean = false,
        val failed: Boolean = false,
    ) {
        val key: String get() = "${board.wire}/$scope/$period"
        val current: Leaderboard? get() = boards[key]
    }

    private val _state = MutableStateFlow(UiState())
    val state: StateFlow<UiState> = _state.asStateFlow()
    private val fetchedAt = mutableMapOf<String, Long>()

    fun start() = viewModelScope.launch { load() }.let { }
    fun selectBoard(b: Board) = viewModelScope.launch { select(board = b) }.let { }
    fun selectScope(s: String) = viewModelScope.launch { select(scope = s) }.let { }
    fun selectPeriod(p: String) = viewModelScope.launch { select(period = p) }.let { }
    fun refresh() = viewModelScope.launch { load(force = true) }.let { }

    suspend fun select(board: Board? = null, scope: String? = null, period: String? = null) {
        _state.update { s ->
            val b = board ?: s.board
            val p = period ?: s.period
            s.copy(board = b, scope = scope ?: s.scope, period = if (p in b.periods) p else b.defaultPeriod)
        }
        load()
    }

    suspend fun load(force: Boolean = false) {
        val key = _state.value.key
        val at = fetchedAt[key]
        if (!force && at != null && now() - at < 60_000) return
        val s = _state.value
        _state.update { it.copy(loading = true) }
        try {
            val board = Leaderboard.decode(service.leaderboard(s.board.wire, s.scope, s.period))
            fetchedAt[key] = now()
            _state.update { it.copy(boards = it.boards + (key to board), failed = false, loading = false) }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            PLog.error { "leaderboard load failed: ${e.message}" }
            _state.update { it.copy(failed = it.boards[key] == null, loading = false) }
        }
    }
}
