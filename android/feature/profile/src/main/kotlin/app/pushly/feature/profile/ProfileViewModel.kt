package app.pushly.feature.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.pushly.core.common.AppError
import app.pushly.core.common.AppErrorCode
import app.pushly.core.common.AuthService
import app.pushly.core.common.PLog
import app.pushly.core.common.Profile
import app.pushly.core.common.ProfilePatch
import app.pushly.core.common.ProfileService
import app.pushly.core.common.ProfileVisibility
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** Profile tab + privacy settings (doc 02 PS-70, PS-73). Same behaviour as iOS ProfileViewModel. */
class ProfileViewModel(
    profile: Profile?,
    private val profiles: ProfileService?,
    private val auth: AuthService?,
    private val onSignedOut: () -> Unit,
    private val onCreateAccount: () -> Unit,
) : ViewModel() {
    enum class Failure { Network, Generic }

    data class UiState(val profile: Profile?, val isSaving: Boolean = false, val failure: Failure? = null) {
        val isGuest: Boolean get() = profile == null
    }

    private val _state = MutableStateFlow(UiState(profile))
    val state: StateFlow<UiState> = _state.asStateFlow()

    fun refresh() {
        val profiles = profiles ?: return
        if (_state.value.profile == null) return
        viewModelScope.launch {
            runCatching { profiles.fetchOwnProfile() }.onSuccess { p -> _state.update { it.copy(profile = p) } }
        }
    }

    fun setVisibility(visibility: ProfileVisibility) =
        save(ProfilePatch(profileVisibility = visibility)) { it.copy(profileVisibility = visibility) }

    fun setLeaderboardVisible(visible: Boolean) =
        save(ProfilePatch(leaderboardVisible = visible)) { it.copy(leaderboardVisible = visible) }

    fun signOut() {
        viewModelScope.launch {
            try {
                auth?.signOut()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // Signing out locally must always work; the server session expires on its own.
                PLog.warning { "Sign-out request failed; clearing local session anyway" }
            }
            onSignedOut()
        }
    }

    fun createAccount() = onCreateAccount()

    /** Optimistic update: apply locally, roll back if the server rejects it. */
    private fun save(patch: ProfilePatch, apply: (Profile) -> Profile) {
        val profiles = profiles ?: return
        val previous = _state.value.profile ?: return
        _state.update { it.copy(profile = apply(previous), isSaving = true, failure = null) }
        viewModelScope.launch {
            try {
                val saved = profiles.updateProfile(patch)
                _state.update { it.copy(profile = saved, isSaving = false) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                val failure = if ((e as? AppError)?.code == AppErrorCode.Network) Failure.Network else Failure.Generic
                _state.update { it.copy(profile = previous, isSaving = false, failure = failure) }
            }
        }
    }
}
