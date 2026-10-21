package app.pushly.feature.profile

import app.pushly.core.common.AccountService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

private class FakeAccount : AccountService {
    var optOut = false
    var failWrites = false
    override suspend fun exportMyData() = "{}"
    override suspend fun deleteMyAccount() = Unit
    override suspend fun notificationPrefs() = "{}"
    override suspend fun setNotificationPrefs(prefsJson: String) = prefsJson
    override suspend fun privacySettings() = """{"ghostOptOut": $optOut}"""
    override suspend fun registerPushToken(deviceId: String, token: String) = Unit
    override suspend fun setGhostOptOut(optOut: Boolean) {
        if (failWrites) throw IllegalStateException("offline")
        this.optOut = optOut
    }
}

/** Same scenarios as iOS AccountModelTests. */
@OptIn(ExperimentalCoroutinesApi::class)
class AccountViewModelTest {
    @Before
    fun setUp() = Dispatchers.setMain(UnconfinedTestDispatcher())

    @After
    fun tearDown() = Dispatchers.resetMain()

    @Test
    fun ghostContributionLoadsAndSaves() = runTest {
        val fake = FakeAccount()
        val vm = AccountViewModel(fake) {}
        vm.load()
        assertTrue(vm.state.value.ghostContribution)
        vm.setGhostContribution(false)
        assertFalse(vm.state.value.ghostContribution)
        assertTrue(fake.optOut)
    }

    @Test
    fun failedSaveRollsBack() = runTest {
        val fake = FakeAccount().apply { failWrites = true }
        val vm = AccountViewModel(fake) {}
        vm.setGhostContribution(false)
        assertTrue(vm.state.value.ghostContribution)
        assertEquals(AccountViewModel.Message.SaveFailed, vm.state.value.message)
    }
}
