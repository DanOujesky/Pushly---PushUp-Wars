package app.pushly.feature.onboarding

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.pushly.core.common.AppError
import app.pushly.core.common.AppErrorCode
import app.pushly.core.common.AuthService
import app.pushly.core.common.EmailRules
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** Sign-in screen logic (doc 02 PS-02): email one-time code. Same behaviour as iOS SignInViewModel. */
class SignInViewModel(
    private val auth: AuthService?,
    private val onSignedIn: (String) -> Unit,
) : ViewModel() {
    sealed interface Step {
        data object EnterEmail : Step
        data class EnterCode(val email: String) : Step
    }

    enum class Failure { InvalidCode, Network, BackendUnavailable, Generic }

    data class UiState(
        val email: String = "",
        val code: String = "",
        val step: Step = Step.EnterEmail,
        val isWorking: Boolean = false,
        val failure: Failure? = null,
        val isBackendAvailable: Boolean = true,
    ) {
        val canSendCode: Boolean get() = !isWorking && isBackendAvailable && EmailRules.isPlausible(email)
        val canVerify: Boolean get() = !isWorking && code.length == 6 && code.all { it in '0'..'9' }
    }

    private val _state = MutableStateFlow(UiState(isBackendAvailable = auth != null))
    val state: StateFlow<UiState> = _state.asStateFlow()

    fun onEmailChange(value: String) = _state.update { it.copy(email = value) }

    fun onCodeChange(value: String) = _state.update { it.copy(code = value.filter { c -> c in '0'..'9' }.take(6)) }

    fun sendCode() {
        val auth = auth ?: return
        val s = _state.value
        if (!s.canSendCode) return
        val address = s.email.trim().lowercase()
        launchAction {
            auth.sendEmailCode(address)
            _state.update { it.copy(code = "", step = Step.EnterCode(address)) }
        }
    }

    fun sendCodeAgain() {
        val auth = auth ?: return
        val step = _state.value.step as? Step.EnterCode ?: return
        launchAction { auth.sendEmailCode(step.email) }
    }

    fun verify() {
        val auth = auth ?: return
        val s = _state.value
        val step = s.step as? Step.EnterCode ?: return
        if (!s.canVerify) return
        launchAction {
            val id = auth.verifyEmailCode(step.email, s.code)
            onSignedIn(id)
        }
    }

    /** [idToken] from Credential Manager (the app does the Google UI). */
    fun signInWithGoogle(idToken: String) {
        val auth = auth ?: return
        launchAction { onSignedIn(auth.signInWithGoogle(idToken)) }
    }

    fun googleFailed() = _state.update { it.copy(failure = Failure.Generic) }

    fun changeEmail() = _state.update { it.copy(step = Step.EnterEmail, code = "", failure = null) }

    private fun launchAction(block: suspend () -> Unit) {
        _state.update { it.copy(isWorking = true, failure = null) }
        viewModelScope.launch {
            val failure = try {
                block()
                null
            } catch (e: CancellationException) {
                throw e
            } catch (e: AppError) {
                when (e.code) {
                    AppErrorCode.Unauthenticated, AppErrorCode.ValidationFailed -> Failure.InvalidCode
                    AppErrorCode.Network -> Failure.Network
                    else -> Failure.Generic
                }
            } catch (e: Exception) {
                Failure.Generic
            }
            _state.update { it.copy(isWorking = false, failure = failure) }
        }
    }
}
