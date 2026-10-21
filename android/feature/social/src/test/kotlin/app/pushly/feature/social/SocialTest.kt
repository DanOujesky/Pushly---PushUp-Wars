package app.pushly.feature.social

import app.pushly.core.common.SocialService
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Same cases as iOS SocialFeatureTests. */
class SocialTest {
    private fun fixture(name: String): String {
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            File(dir, "shared/contracts/fixtures/$name").takeIf { it.exists() }?.let { return it.readText() }
            dir = dir.parentFile
        }
        error("fixture not found: $name")
    }

    private open class FakeService(
        val friends: String = "{}",
        val feed: String = "[]",
        val board: String = "{}",
    ) : SocialService {
        var boardCalls = 0
        override suspend fun listFriends() = friends
        override suspend fun searchUsers(query: String) = "[]"
        override suspend fun sendFriendRequest(userId: String) = "pending"
        override suspend fun respondFriendRequest(userId: String, accept: Boolean) = "friends"
        override suspend fun removeFriend(userId: String) = "none"
        override suspend fun blockUser(userId: String) = "blocked"
        override suspend fun unblockUser(userId: String) = "none"
        override suspend fun friendFeed() = feed
        override suspend fun giveKudos(eventId: Long): Int = throw IllegalStateException("refused")
        override suspend fun leaderboard(board: String, scope: String, period: String): String {
            boardCalls++
            return this.board
        }
    }

    @Test
    fun decodesFixtures() {
        val board = Leaderboard.decode(fixture("leaderboard.json"))
        assertEquals(4, board.rows.size)
        assertEquals(true, board.rows[0].user.anonymous)
        assertEquals(3, board.me?.rank)
        assertEquals(2, FriendsList.decode(fixture("friends.json")).friends.size)
        val feed = FeedItem.decodeList(fixture("friend_feed.json"))
        assertEquals(25, feed.first().int("reps"))
        assertEquals(R.string.social_feed_wake to 25, describe(feed.first()))
        assertEquals("friends", UserCard.decodeList(fixture("user_search.json")).first().relation)
    }

    @Test
    fun kudosIsOptimisticAndRollsBack() = runTest {
        val raw = SocialJson.parseToJsonElement(fixture("friend_feed.json")).jsonArray
        val item = JsonObject(raw[0].jsonObject + mapOf("kudosByMe" to JsonPrimitive(false), "kudos" to JsonPrimitive(0)))
        val vm = FriendsViewModel(FakeService(friends = fixture("friends.json"), feed = JsonArray(listOf(item)).toString()))
        vm.load()
        assertEquals(1, vm.state.value.feed.size)
        vm.kudos(vm.state.value.feed[0])
        assertEquals(0, vm.state.value.feed[0].kudos)
        assertFalse(vm.state.value.feed[0].kudosByMe)
    }

    @Test
    fun ranksCacheAndPinnedMe() = runTest {
        val raw = SocialJson.parseToJsonElement(fixture("leaderboard.json")).jsonObject
        val rows = raw.getValue("rows").jsonArray.filterIndexed { i, _ -> i != 2 }
        val data = JsonObject(raw + mapOf("rows" to JsonArray(rows))).toString()
        var now = 0L
        val service = FakeService(board = data)
        val vm = RanksViewModel(service) { now }
        vm.load()
        vm.load()
        assertEquals(1, service.boardCalls)
        now = 61_000
        vm.load()
        assertEquals(2, service.boardCalls)
        assertEquals(3, vm.state.value.current?.pinnedMe?.rank)
        assertTrue(vm.state.value.current?.pinnedMe?.isMe == true)
        vm.select(board = Board.Streak)
        assertEquals("current", vm.state.value.period)
    }
}
