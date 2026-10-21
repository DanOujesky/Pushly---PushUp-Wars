package app.pushly

import app.pushly.core.common.AccountService
import app.pushly.core.common.AppError
import app.pushly.core.common.AppErrorCode
import app.pushly.core.common.AppVersion
import app.pushly.core.common.AuthService
import app.pushly.core.common.BattleService
import app.pushly.core.common.ClanService
import app.pushly.core.common.KeyValueStore
import app.pushly.core.common.LegalLinks
import app.pushly.core.common.PLog
import app.pushly.core.common.Profile
import app.pushly.core.common.ProfileService
import app.pushly.core.common.RemoteConfig
import app.pushly.core.common.RemoteConfigService
import app.pushly.core.common.SocialService
import app.pushly.core.common.StatsService
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Top-level app state machine (doc 02 §2): launch → (update required) → welcome/sign-in → profile setup → main tabs.
 * Same states and rules as iOS AppSession.
 */
class AppSession(
    val auth: AuthService?,
    val profiles: ProfileService?,
    private val remoteConfig: RemoteConfigService?,
    private val store: KeyValueStore,
    private val appVersion: String,
    /** Stats tab + achievements (null in guest-only builds). */
    val stats: StatsService? = null,
    /** Friends, feed and leaderboards (null in guest-only builds). */
    val social: SocialService? = null,
    /** Clans (null in guest-only builds). */
    val clans: ClanService? = null,
    /** Account & data (null in guest-only builds). */
    val account: AccountService? = null,
    /** Battles (null in guest-only builds). */
    val battles: BattleService? = null,
) {
    sealed interface State {
        data object Launching : State
        data object UpdateRequired : State
        data object Welcome : State
        data object SignIn : State
        data class ProfileSetup(val profile: Profile) : State
        /** profile == null → guest (alarm only). */
        data class Main(val profile: Profile?) : State
    }

    private val _state = MutableStateFlow<State>(State.Launching)
    val state: StateFlow<State> = _state.asStateFlow()

    var config: RemoteConfig = RemoteConfig()
        private set

    /** Set when an email sign-in link could not be used (expired or opened on another device). */
    private val _linkSignInFailed = MutableStateFlow(false)
    val linkSignInFailed: StateFlow<Boolean> = _linkSignInFailed.asStateFlow()

    /** Debug builds only: fixed start screen for the CI screenshot job (`--es debugScreen <name>`). */
    var debugStartState: State? = null

    suspend fun start() {
        debugStartState?.let {
            _state.value = it
            return
        }
        remoteConfig?.let { service ->
            val fetched = try {
                service.fetch()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                null
            }
            if (fetched != null) {
                config = fetched
                if (AppVersion.updateRequired(appVersion, fetched.minSupportedVersion)) {
                    _state.value = State.UpdateRequired
                    return
                }
            }
        }
        route()
    }

    suspend fun route() {
        when {
            auth != null && auth.currentUserId() != null -> loadProfileAndRoute()
            store.getBoolean(KEY_GUEST) -> _state.value = State.Main(null)
            store.getBoolean(KEY_WELCOME_SEEN) -> _state.value = State.SignIn
            else -> _state.value = State.Welcome
        }
    }

    fun welcomeFinished() {
        store.putBoolean(KEY_WELCOME_SEEN, true)
        // "Get started" accepts the Terms / Privacy Policy of this version (doc 16 §3).
        store.putBoolean(KEY_LEGAL_ACCEPTED_PREFIX + LegalLinks.VERSION, true)
        _state.value = State.SignIn
    }

    suspend fun signedIn() {
        store.putBoolean(KEY_GUEST, false)
        loadProfileAndRoute()
    }

    /** Email-link sign-in: the link opens the app with `pushly://auth-callback?code=...`. */
    suspend fun handleAuthCallback(url: String) {
        val auth = auth ?: return
        try {
            auth.handleAuthCallback(url)
            _linkSignInFailed.value = false
            signedIn()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            PLog.warning { "Email link sign-in failed" }
            _linkSignInFailed.value = true
        }
    }

    fun continueAsGuest() {
        store.putBoolean(KEY_GUEST, true)
        _state.value = State.Main(null)
    }

    fun profileCompleted(profile: Profile) {
        _state.value = State.Main(profile)
    }

    fun signedOut() {
        store.putBoolean(KEY_GUEST, false)
        _state.value = State.SignIn
    }

    fun createAccountFromGuest() {
        store.putBoolean(KEY_GUEST, false)
        _state.value = State.SignIn
    }

    private suspend fun loadProfileAndRoute() {
        val profiles = profiles ?: run {
            _state.value = State.Main(null)
            return
        }
        _state.value = try {
            val profile = profiles.fetchOwnProfile()
            if (profile.onboardingCompleted) State.Main(profile) else State.ProfileSetup(profile)
        } catch (e: CancellationException) {
            throw e
        } catch (e: AppError) {
            if (e.code == AppErrorCode.Unauthenticated) {
                State.SignIn
            } else {
                PLog.warning(PLog.Category.Sync) { "Profile fetch failed at launch: ${e.code}" }
                State.Main(null)
            }
        } catch (e: Exception) {
            PLog.warning(PLog.Category.Sync) { "Profile fetch failed at launch" }
            State.Main(null)
        }
    }

    companion object {
        const val KEY_GUEST = "session.guestMode"
        const val KEY_WELCOME_SEEN = "session.welcomeSeen"
        const val KEY_LEGAL_ACCEPTED_PREFIX = "session.legalAccepted."
    }
}
