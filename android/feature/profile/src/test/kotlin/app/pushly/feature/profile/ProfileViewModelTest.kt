package app.pushly.feature.profile

import app.pushly.core.common.AppError
import app.pushly.core.common.AppErrorCode
import app.pushly.core.common.InMemoryBackend
import app.pushly.core.common.Profile
import app.pushly.core.common.ProfilePatch
import app.pushly.core.common.ProfileVisibility
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** Same scenarios as iOS ProfileViewModelTests. */
@OptIn(ExperimentalCoroutinesApi::class)
class ProfileViewModelTest {
    @Before
    fun setUp() = Dispatchers.setMain(UnconfinedTestDispatcher())

    @After
    fun tearDown() = Dispatchers.resetMain()

    private suspend fun signedIn(): Pair<InMemoryBackend, Profile> {
        val backend = InMemoryBackend(currentYear = 2026)
        backend.signInDirectly()
        return backend to backend.updateProfile(ProfilePatch(username = "AnaFit2", birthYear = 2000))
    }

    @Test
    fun privacyChangesAreSaved() = runTest {
        val (backend, profile) = signedIn()
        val vm = ProfileViewModel(profile, backend, backend, {}, {})
        vm.setVisibility(ProfileVisibility.Friends)
        vm.setLeaderboardVisible(false)
        assertEquals(ProfileVisibility.Friends, vm.state.value.profile?.profileVisibility)
        assertEquals(false, vm.state.value.profile?.leaderboardVisible)
        assertEquals(ProfileVisibility.Friends, backend.profile?.profileVisibility)
    }

    @Test
    fun failedSaveRollsBack() = runTest {
        val (backend, profile) = signedIn()
        val vm = ProfileViewModel(profile, backend, backend, {}, {})
        backend.nextError = AppError(AppErrorCode.Network, "offline")
        vm.setVisibility(ProfileVisibility.Private)
        assertEquals(ProfileVisibility.Public, vm.state.value.profile?.profileVisibility)
        assertEquals(ProfileViewModel.Failure.Network, vm.state.value.failure)
    }

    @Test
    fun signOutAlwaysCompletesLocally() = runTest {
        val (backend, profile) = signedIn()
        var signedOut = false
        val vm = ProfileViewModel(profile, backend, backend, { signedOut = true }, {})
        backend.nextError = AppError(AppErrorCode.Network, "offline")
        vm.signOut()
        assertTrue(signedOut)
    }

    @Test
    fun guestMode() {
        val vm = ProfileViewModel(null, null, null, {}, {})
        assertTrue(vm.state.value.isGuest)
    }
}
