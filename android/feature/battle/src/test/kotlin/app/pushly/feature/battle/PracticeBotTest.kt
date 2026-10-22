package app.pushly.feature.battle

import app.pushly.core.common.BattleService
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test

/** Practice bots (D-063): always shown as bots, started through `start_bot_battle`, rematch keeps the level. Same as iOS. */
@OptIn(ExperimentalCoroutinesApi::class)
class PracticeBotTest {
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

    private fun battleJson(bot: String?): String {
        val base = Json.parseToJsonElement(read("shared/contracts/fixtures/battle.json")).jsonObject
        val name = bot?.let { "Bot · " + it.replaceFirstChar(Char::uppercase) } ?: "Ghost"
        return JsonObject(
            base + mapOf(
                "type" to JsonPrimitive("ghost"),
                "ranked" to JsonPrimitive(false),
                "ghost" to JsonPrimitive(true),
                "bot" to (bot?.let { JsonPrimitive(it) } ?: JsonNull),
                "opponent" to JsonObject(mapOf("username" to JsonPrimitive(name))),
            ),
        ).toString()
    }

    private inner class Fake : BattleService {
        val bots = ArrayList<Pair<String, String?>>()
        override suspend fun battleInvites(): String = error("unused")
        override suspend fun createBattleInvite(toUser: String, mode: String, ranked: Boolean): String = error("unused")
        override suspend fun respondBattleInvite(id: String, accept: Boolean): String = error("unused")
        override suspend fun matchmakingJoin(mode: String): String = error("unused")
        override suspend fun matchmakingStatus(): String = error("unused")
        override suspend fun matchmakingLeave() = Unit
        override suspend fun battle(id: String): String = error("unused")
        override suspend fun battleReady(id: String): String = error("unused")
        override suspend fun battlePushReps(id: String, repsJson: String) = Unit
        override suspend fun battleFinish(id: String): String = error("unused")
        override suspend fun battleForfeit(id: String): String = error("unused")
        override suspend fun battleHistory(): String = error("unused")
        override suspend fun startGhostBattle(mode: String): String = error("unused")
        override suspend fun seasonHistory(): String = error("unused")
        override suspend fun startBotBattle(mode: String, level: String?): String {
            bots += mode to level
            return battleJson(level ?: "rookie")
        }
    }

    @Test
    fun botsAreAlwaysMarked() {
        assertEquals("🤖 Bot · Athlete", Battle.decode(battleJson("athlete")).opponentDisplayName)
        assertEquals("Ghost", Battle.decode(battleJson(null)).opponentDisplayName)
    }

    @Test
    fun practiceStartsABotBattle() = runTest {
        val fake = Fake()
        val vm = BattleHubViewModel(fake, null)
        vm.practice(BattleMode.Speed, BotLevel.Pro)
        assertEquals(listOf("speed" to "pro"), fake.bots)
        assertEquals("pro", vm.state.value.active?.bot)
    }

    @Test
    fun rematchAgainstABotKeepsTheLevel() = runTest {
        val fake = Fake()
        val vm = BattleHubViewModel(fake, null)
        vm.rematch(Battle.decode(battleJson("champion")))
        assertEquals("champion", fake.bots.single().second)
    }

    @Test
    fun levelsOrderedWeakestFirst() {
        assertEquals(listOf("beginner", "rookie", "athlete", "pro", "champion"), BotLevel.entries.map { it.wire })
    }
}
