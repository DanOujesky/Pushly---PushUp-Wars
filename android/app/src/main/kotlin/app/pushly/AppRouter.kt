package app.pushly

import app.pushly.core.common.DeepLink
import app.pushly.core.common.PLog
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** The five main tabs (doc 02 §1). */
enum class AppTab { Wake, Battle, Clan, Training, Profile }

/** App-wide navigation state; features never navigate to each other directly (doc 03 §3). */
class AppRouter {
    private val _selectedTab = MutableStateFlow(AppTab.Wake)
    val selectedTab: StateFlow<AppTab> = _selectedTab.asStateFlow()

    private var pendingLink: DeepLink? = null

    /** A player profile shown over the current tab (pushly://u/{username} or a tap on a friend). */
    data class ProfileKey(val userId: String? = null, val username: String? = null)

    private val _profile = MutableStateFlow<ProfileKey?>(null)
    val profile: StateFlow<ProfileKey?> = _profile.asStateFlow()

    fun openProfile(key: ProfileKey?) {
        _profile.value = key
    }

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
        if (link is DeepLink.User) {
            _profile.value = ProfileKey(username = link.username)
            return
        }
        _selectedTab.value = tabFor(link)
        pendingLink = link
    }

    fun consumePendingLink(): DeepLink? = pendingLink.also { pendingLink = null }

    companion object {
        fun tabFor(link: DeepLink): AppTab = when (link) {
            DeepLink.Wake, is DeepLink.Alarm, DeepLink.AlarmHealth -> AppTab.Wake
            is DeepLink.Battle, is DeepLink.BattleInvite, is DeepLink.Leaderboard -> AppTab.Battle
            is DeepLink.Clan, is DeepLink.ClanWar -> AppTab.Clan
            is DeepLink.User, DeepLink.Pro -> AppTab.Profile
        }
    }
}
