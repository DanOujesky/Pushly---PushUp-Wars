package app.pushly.feature.onboarding

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.pushly.core.common.AccountRules
import app.pushly.core.common.AppError
import app.pushly.core.common.AppErrorCode
import app.pushly.core.common.Profile
import app.pushly.core.common.ProfilePatch
import app.pushly.core.common.ProfileService
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.util.Locale

/** Profile setup after the first sign-in (doc 02 PS-03). Same behaviour as iOS ProfileSetupViewModel. */
class ProfileSetupViewModel(
    profile: Profile,
    private val profiles: ProfileService,
    private val currentYear: Int = java.time.Year.now().value,
    regionCode: String? = Locale.getDefault().country,
    private val timeZoneId: String = java.util.TimeZone.getDefault().id,
    private val debounceMs: Long = 400,
    private val onCompleted: (Profile) -> Unit,
) : ViewModel() {
    sealed interface Availability {
        data object Idle : Availability
        data object Checking : Availability
        data object Available : Availability
        data object Taken : Availability
        data class Invalid(val error: AccountRules.UsernameError) : Availability
        data object Unknown : Availability
    }

    enum class Failure { UsernameTaken, TooYoung, Network, Generic }

    data class UiState(
        val username: String,
        val presetId: String,
        val country: String?,
        val birthYear: Int?,
        val availability: Availability = Availability.Idle,
        val isSaving: Boolean = false,
        val failure: Failure? = null,
    )

    val birthYearOptions: List<Int> = AccountRules.selectableBirthYears(currentYear)

    private val _state = MutableStateFlow(
        UiState(
            // Never prefill the placeholder username (u_xxxxxxxxxxxx).
            username = if (AccountRules.usernameError(profile.username) == null) profile.username else "",
            presetId = profile.avatarPreset ?: "preset.flame",
            country = profile.country ?: regionCode?.takeIf { CountryList.isKnown(it) },
            birthYear = profile.birthYear,
        ),
    )
    val state: StateFlow<UiState> = _state.asStateFlow()

    private var checkJob: Job? = null

    val canSubmit: Boolean
        get() {
            val s = _state.value
            val year = s.birthYear ?: return false
            return !s.isSaving && AccountRules.usernameError(s.username) == null &&
                AccountRules.birthYearError(year, currentYear) == null &&
                (s.availability == Availability.Available || s.availability == Availability.Unknown)
        }

    fun onUsernameChange(value: String) {
        _state.update { it.copy(username = value, failure = null) }
        checkJob?.cancel()
        val error = AccountRules.usernameError(value)
        if (error != null) {
            _state.update { it.copy(availability = if (value.isEmpty()) Availability.Idle else Availability.Invalid(error)) }
            return
        }
        _state.update { it.copy(availability = Availability.Checking) }
        checkJob = viewModelScope.launch {
            delay(debounceMs)
            checkAvailability(value)
        }
    }

    suspend fun checkAvailability(name: String) {
        val result = try {
            if (profiles.isUsernameAvailable(name)) Availability.Available else Availability.Taken
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Availability.Unknown
        }
        if (name == _state.value.username) _state.update { it.copy(availability = result) }
    }

    fun onPresetChange(id: String) = _state.update { it.copy(presetId = id) }

    fun onCountryChange(code: String?) = _state.update { it.copy(country = code) }

    fun onBirthYearChange(year: Int?) = _state.update { it.copy(birthYear = year) }

    fun submit() {
        if (!canSubmit) return
        val s = _state.value
        _state.update { it.copy(isSaving = true, failure = null) }
        viewModelScope.launch {
            try {
                val updated = profiles.updateProfile(
                    ProfilePatch(username = s.username, avatarPreset = s.presetId, country = s.country,
                        birthYear = s.birthYear, timezone = timeZoneId),
                )
                _state.update { it.copy(isSaving = false) }
                onCompleted(updated)
            } catch (e: CancellationException) {
                throw e
            } catch (e: AppError) {
                val failure = when {
                    e.code == AppErrorCode.Conflict -> Failure.UsernameTaken
                    e.code == AppErrorCode.ValidationFailed && e.message.contains("16") -> Failure.TooYoung
                    e.code == AppErrorCode.Network -> Failure.Network
                    else -> Failure.Generic
                }
                _state.update {
                    it.copy(
                        isSaving = false,
                        failure = failure,
                        availability = if (failure == Failure.UsernameTaken) Availability.Taken else it.availability,
                    )
                }
            } catch (e: Exception) {
                _state.update { it.copy(isSaving = false, failure = Failure.Generic) }
            }
        }
    }
}

/** ISO 3166 countries with localized names, for the country picker. */
object CountryList {
    data class Country(val code: String, val name: String) {
        val flag: String
            get() = code.uppercase().map { Character.toChars(0x1F1E6 + (it - 'A')).concatToString() }.joinToString("")
    }

    private val codes: Set<String> = Locale.getISOCountries().toSet()

    fun all(locale: Locale = Locale.getDefault()): List<Country> =
        codes.map { Country(it, Locale.Builder().setRegion(it).build().getDisplayCountry(locale)) }
            .filter { it.name.isNotBlank() }
            .sortedBy { it.name }

    fun isKnown(code: String): Boolean = code in codes
}
