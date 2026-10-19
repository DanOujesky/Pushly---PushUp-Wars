package app.pushly

import app.pushly.core.common.DeepLink
import app.pushly.core.common.PLog
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** The five main tabs (doc 02 §1). */
enum class AppTab { Wake, Battle, Clan, Ranks, Profile }

/** App-wide navigation state; features never navigate to each other directly (doc 03 §3). */
class AppRouter {
    private val _selectedTab = MutableStateFlow(AppTab.Wake)
    val selectedTab: StateFlow<AppTab> = _selectedTab.asStateFlow()

    private var pendingLink: DeepLink? = null

    fun select(tab: AppTab) {
        _selectedTab.value = tab
    }

    fun handle(url: String) {
        val link = DeepLink.parse(url)
        if (link == null) {
            PLog.warning { "Ignored unknown deep link" }
            return
        }
        open(link)
    }

    fun open(link: DeepLink) {
        _selectedTab.value = tabFor(link)
        pendingLink = link
    }

    fun consumePendingLink(): DeepLink? = pendingLink.also { pendingLink = null }

    companion object {
        fun tabFor(link: DeepLink): AppTab = when (link) {
            DeepLink.Wake, is DeepLink.Alarm, DeepLink.AlarmHealth -> AppTab.Wake
            is DeepLink.Battle, is DeepLink.BattleInvite -> AppTab.Battle
            is DeepLink.Clan, is DeepLink.ClanWar -> AppTab.Clan
            is DeepLink.Leaderboard -> AppTab.Ranks
            is DeepLink.User, DeepLink.Pro -> AppTab.Profile
        }
    }
}
