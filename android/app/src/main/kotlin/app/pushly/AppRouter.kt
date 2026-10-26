package app.pushly

import app.pushly.core.common.DeepLink
import app.pushly.core.common.PLog
import app.pushly.core.designsystem.ProfileTarget
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** The five main tabs (doc 02 §1). */
enum class AppTab { Wake, Battle, Clan, Training, Profile }

/** App-wide navigation state; features never navigate to each other directly (doc 03 §3). */
class AppRouter {
    // Battle is the home screen (D-076); an alarm or a link still switches to its tab.
    private val _selectedTab = MutableStateFlow(AppTab.Battle)
    val selectedTab: StateFlow<AppTab> = _selectedTab.asStateFlow()

    private var pendingLink: DeepLink? = null

    /** A player profile shown over the current tab (pushly://u/{username} or a tap on a friend). */
    data class ProfileKey(val userId: String? = null, val username: String? = null)

    /** Player / clan pages over everything, newest on top (D-080). */
    private val _pages = MutableStateFlow<List<ProfileTarget>>(emptyList())
    val pages: StateFlow<List<ProfileTarget>> = _pages.asStateFlow()

    fun push(target: ProfileTarget) {
        _pages.value = (_pages.value + target).takeLast(8)
    }

    fun pop() {
        _pages.value = _pages.value.dropLast(1)
    }

    fun openProfile(key: ProfileKey?) {
        when {
            key == null -> pop()
            key.userId != null -> push(ProfileTarget.User(key.userId))
            key.username != null -> push(ProfileTarget.Username(key.username))
        }
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
            push(ProfileTarget.Username(link.username))
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
