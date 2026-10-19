package app.pushly.feature.onboarding

import app.pushly.core.common.AppError
import app.pushly.core.common.AppErrorCode
import app.pushly.core.common.InMemoryBackend
import app.pushly.core.common.Profile
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** Same scenarios as iOS OnboardingViewModelTests. */
@OptIn(ExperimentalCoroutinesApi::class)
class OnboardingViewModelTest {
    @Before
    fun setUp() = Dispatchers.setMain(UnconfinedTestDispatcher())

    @After
    fun tearDown() = Dispatchers.resetMain()

    @Test
    fun emailCodeFlowSignsIn() = runTest {
        val backend = InMemoryBackend()
        var signedIn: String? = null
        val vm = SignInViewModel(backend) { signedIn = it }

        vm.onEmailChange("not-an-email")
        assertFalse(vm.state.value.canSendCode)
        vm.onEmailChange("  Dan@Example.com ")
        assertTrue(vm.state.value.canSendCode)
        vm.sendCode()
        assertEquals(SignInViewModel.Step.EnterCode("dan@example.com"), vm.state.value.step)
        assertEquals(listOf("dan@example.com"), backend.sentCodes)

        vm.onCodeChange("12345")
        assertFalse(vm.state.value.canVerify)
        vm.onCodeChange("000000")
        vm.verify()
        assertEquals(SignInViewModel.Failure.InvalidCode, vm.state.value.failure)
        assertNull(signedIn)

        vm.onCodeChange("123456")
        vm.verify()
        assertNull(vm.state.value.failure)
        assertNotNull(signedIn)
    }

    @Test
    fun networkErrorIsReported() = runTest {
        val backend = InMemoryBackend().apply { nextError = AppError(AppErrorCode.Network, "offline") }
        val vm = SignInViewModel(backend) {}
        vm.onEmailChange("dan@example.com")
        vm.sendCode()
        assertEquals(SignInViewModel.Failure.Network, vm.state.value.failure)
        assertEquals(SignInViewModel.Step.EnterEmail, vm.state.value.step)
        assertFalse(vm.state.value.isWorking)
    }

    @Test
    fun withoutBackendOnlyGuestIsPossible() {
        val vm = SignInViewModel(null) {}
        assertFalse(vm.state.value.isBackendAvailable)
        vm.onEmailChange("dan@example.com")
        assertFalse(vm.state.value.canSendCode)
    }

    private suspend fun signedInProfile(backend: InMemoryBackend): Profile {
        backend.signInDirectly()
        return backend.fetchOwnProfile()
    }

    private fun setupVm(backend: InMemoryBackend, profile: Profile, onCompleted: (Profile) -> Unit = {}) =
        ProfileSetupViewModel(profile, backend, currentYear = 2026, regionCode = "CZ", timeZoneId = "Europe/Prague",
            debounceMs = 0, onCompleted = onCompleted)

    @Test
    fun placeholderUsernameIsNotPrefilled() = runTest {
        val backend = InMemoryBackend(currentYear = 2026)
        val vm = setupVm(backend, signedInProfile(backend))
        assertEquals("", vm.state.value.username)
        assertEquals("CZ", vm.state.value.country)
        assertEquals(2010, vm.birthYearOptions.first())
    }

    @Test
    fun availabilityAndSubmit() = runTest {
        val backend = InMemoryBackend(currentYear = 2026)
        var completed: Profile? = null
        val vm = setupVm(backend, signedInProfile(backend)) { completed = it }

        vm.onUsernameChange("a!")
        assertEquals(ProfileSetupViewModel.Availability.Invalid(app.pushly.core.common.AccountRules.UsernameError.TooShort), vm.state.value.availability)

        vm.onUsernameChange("Taken")
        assertEquals(ProfileSetupViewModel.Availability.Taken, vm.state.value.availability)

        vm.onUsernameChange("DanPushes")
        assertEquals(ProfileSetupViewModel.Availability.Available, vm.state.value.availability)
        assertFalse(vm.canSubmit)

        vm.onBirthYearChange(2004)
        assertTrue(vm.canSubmit)
        vm.submit()
        val profile = completed
        assertNotNull(profile)
        assertEquals("DanPushes", profile?.username)
        assertEquals(true, profile?.onboardingCompleted)
        assertEquals("CZ", profile?.country)
        assertEquals("Europe/Prague", profile?.timezone)
    }

    @Test
    fun raceOnUsernameIsHandled() = runTest {
        val backend = InMemoryBackend(currentYear = 2026)
        val vm = setupVm(backend, signedInProfile(backend))
        vm.onUsernameChange("DanPushes")
        vm.onBirthYearChange(2000)
        backend.nextError = AppError(AppErrorCode.Conflict, "taken")
        vm.submit()
        assertEquals(ProfileSetupViewModel.Failure.UsernameTaken, vm.state.value.failure)
        assertEquals(ProfileSetupViewModel.Availability.Taken, vm.state.value.availability)
    }

    @Test
    fun staleAvailabilityResultIsIgnored() = runTest {
        val backend = InMemoryBackend(currentYear = 2026)
        val vm = setupVm(backend, signedInProfile(backend))
        vm.checkAvailability("OldName")
        assertEquals(ProfileSetupViewModel.Availability.Idle, vm.state.value.availability)
    }

    @Test
    fun countryListHasFlags() {
        val cz = CountryList.all(java.util.Locale.US).firstOrNull { it.code == "CZ" }
        assertNotNull(cz)
        assertEquals("🇨🇿", cz?.flag)
    }
}
