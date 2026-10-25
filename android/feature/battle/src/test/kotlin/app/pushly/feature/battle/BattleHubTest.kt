package app.pushly.feature.battle

import app.pushly.core.common.BattleService
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** Battle lobby (D-071): arena header from get_battle_stats, friend challenges are always friendly. Same as iOS. */
@OptIn(ExperimentalCoroutinesApi::class)
class BattleHubTest {
    @Before
    fun setUp() = Dispatchers.setMain(UnconfinedTestDispatcher())

    @After
    fun tearDown() = Dispatchers.resetMain()

    private fun read(relative: String): String {
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            File(dir, relative).takeIf { it.exists() }?.let { return it.readText() }
            dir = dir.parentFile
        }
        error("not found: $relative")
    }

    private class Fake : BattleService {
        val ranked = ArrayList<Boolean>()
        override suspend fun battleInvites(): String = """{"incoming":[],"outgoing":[]}"""
        override suspend fun createBattleInvite(toUser: String, mode: String, ranked: Boolean): String {
            this.ranked += ranked
            return "{}"
        }
        override suspend fun respondBattleInvite(id: String, accept: Boolean): String = error("unused")
        override suspend fun matchmakingJoin(mode: String): String = error("unused")
        override suspend fun matchmakingStatus(): String = error("unused")
        override suspend fun matchmakingLeave() = Unit
        override suspend fun battle(id: String): String = error("unused")
        override suspend fun battleReady(id: String): String = error("unused")
        override suspend fun battlePushReps(id: String, repsJson: String) = Unit
        override suspend fun battleFinish(id: String): String = error("unused")
        override suspend fun battleForfeit(id: String): String = error("unused")
        override suspend fun battleHistory(): String = "[]"
        override suspend fun startGhostBattle(mode: String): String = error("unused")
        override suspend fun seasonHistory(): String = "[]"
    }

    @Test
    fun arenaComesFromBattleStats() = runTest {
        val stats = read("shared/contracts/fixtures/battle_stats.json")
        val vm = BattleHubViewModel(Fake(), null, { stats })
        vm.load()
        val arena = vm.state.value.arena
        assertNotNull(arena)
        assertEquals(1340, arena!!.trophies)
        assertEquals("gold", arena.league)
        assertEquals(482, arena.rank)
        // gold III starts at 1200, next step 1466 → (1340 − 1200) / 266
        assertEquals(140f / 266f, arena.progress, 0.0001f)
    }

    @Test
    fun friendChallengesAreNeverRanked() = runTest {
        val fake = Fake()
        val vm = BattleHubViewModel(fake, null)
        vm.challenge(FriendPick("f1", "kamo"), BattleMode.Speed)
        assertEquals(listOf(false), fake.ranked)
    }

    @Test
    fun topLeagueHasFullProgress() {
        val arena = ArenaStatus.decode(read("shared/contracts/fixtures/battle_stats.json")).copy(next = null)
        assertEquals(1f, arena.progress)
        assertTrue(arena.seasonDaysLeft(0) != null)
    }
}
