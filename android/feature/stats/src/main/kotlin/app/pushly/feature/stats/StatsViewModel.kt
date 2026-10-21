package app.pushly.feature.stats

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.pushly.core.common.PLog
import app.pushly.core.common.StatsService
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** Loads the Stats screen (doc 10 §2) and the achievements list. Periods are cached. Same behaviour as iOS StatsModel. */
class StatsViewModel(private val service: StatsService) : ViewModel() {
    data class AchievementGroup(val group: String, val items: List<AchievementItem>)

    data class UiState(
        val period: StatsData.Period = StatsData.Period.Week,
        val cache: Map<StatsData.Period, StatsData> = emptyMap(),
        val achievements: List<AchievementItem> = emptyList(),
        val loading: Boolean = false,
        val failed: Boolean = false,
    ) {
        val stats: StatsData? get() = cache[period]

        /** Achievements grouped in definition order. */
        val groups: List<AchievementGroup>
            get() = achievements.groupBy { it.group }.map { (g, items) -> AchievementGroup(g, items) }
    }

    private val _state = MutableStateFlow(UiState())
    val state: StateFlow<UiState> = _state.asStateFlow()

    fun start() {
        viewModelScope.launch {
            if (_state.value.stats == null) load()
            if (_state.value.achievements.isEmpty()) loadAchievements()
        }
    }

    fun selectPeriod(period: StatsData.Period) {
        viewModelScope.launch { select(period) }
    }

    fun reload() {
        viewModelScope.launch { refresh() }
    }

    suspend fun select(period: StatsData.Period) {
        _state.update { it.copy(period = period) }
        if (_state.value.cache[period] == null) load()
    }

    suspend fun load() {
        val wanted = _state.value.period
        _state.update { it.copy(loading = true) }
        try {
            val data = StatsData.decode(service.stats(wanted.wire))
            _state.update { it.copy(cache = it.cache + (wanted to data), failed = false, loading = false) }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            PLog.error { "stats load failed: ${e.message}" }
            _state.update { it.copy(failed = it.cache[wanted] == null, loading = false) }
        }
    }

    suspend fun refresh() {
        _state.update { it.copy(cache = emptyMap()) }
        load()
        loadAchievements()
    }

    suspend fun loadAchievements() {
        try {
            val items = AchievementItem.decodeList(service.achievements())
            _state.update { it.copy(achievements = items) }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            PLog.error { "achievements load failed: ${e.message}" }
        }
    }
}
