package app.pushly

import app.pushly.core.common.AppError
import app.pushly.core.common.AppErrorCode
import app.pushly.core.common.InMemoryBackend
import app.pushly.core.common.InMemoryKeyValueStore
import app.pushly.core.common.ProfilePatch
import app.pushly.core.common.RemoteConfig
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Same scenarios as iOS AppSessionTests. */
class AppSessionTest {
    @Test
    fun firstLaunchShowsWelcomeThenSignIn() = runTest {
        val backend = InMemoryBackend()
        val session = AppSession(backend, backend, backend, InMemoryKeyValueStore(), "1.0.0")
        session.start()
        assertEquals(AppSession.State.Welcome, session.state.value)
        session.welcomeFinished()
        assertEquals(AppSession.State.SignIn, session.state.value)
    }

    @Test
    fun oldVersionIsBlocked() = runTest {
        val backend = InMemoryBackend().apply { config = RemoteConfig(minSupportedVersion = "1.2.0") }
        val session = AppSession(backend, backend, backend, InMemoryKeyValueStore(), "1.1.9")
        session.start()
        assertEquals(AppSession.State.UpdateRequired, session.state.value)
    }

    @Test
    fun newUserGoesToProfileSetupThenMain() = runTest {
        val backend = InMemoryBackend(currentYear = 2026)
        val session = AppSession(backend, backend, null, InMemoryKeyValueStore(), "1.0.0")
        backend.signInDirectly()
        session.signedIn()
        assertTrue(session.state.value is AppSession.State.ProfileSetup)
        val done = backend.updateProfile(ProfilePatch(username = "DanPushes", birthYear = 2001))
        session.profileCompleted(done)
        assertEquals(AppSession.State.Main(done), session.state.value)

        val relaunch = AppSession(backend, backend, null, InMemoryKeyValueStore(), "1.0.0")
        relaunch.start()
        assertEquals(AppSession.State.Main(done), relaunch.state.value)
    }

    @Test
    fun guestModeIsRemembered() = runTest {
        val store = InMemoryKeyValueStore()
        val session = AppSession(null, null, null, store, "1.0.0")
        session.continueAsGuest()
        assertEquals(AppSession.State.Main(null), session.state.value)
        val relaunch = AppSession(null, null, null, store, "1.0.0")
        relaunch.start()
        assertEquals(AppSession.State.Main(null), relaunch.state.value)
        relaunch.createAccountFromGuest()
        assertEquals(AppSession.State.SignIn, relaunch.state.value)
    }

    @Test
    fun offlineConfigDoesNotBlockLaunch() = runTest {
        val backend = InMemoryBackend().apply { nextError = AppError(AppErrorCode.Network, "offline") }
        val session = AppSession(backend, backend, backend, InMemoryKeyValueStore(), "1.0.0")
        session.start()
        assertEquals(AppSession.State.Welcome, session.state.value)
    }
}
