package app.pushly.core.common

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Same vectors as iOS AdsGateTests. */
class AdsGateTest {
    @Serializable data class Case(val id: String, val placement: String, val context: AdsGate.Context, val allowed: Boolean, val reason: String)
    @Serializable data class File(val cases: List<Case>)

    @Test
    fun sharedVectors() {
        val file = Json { ignoreUnknownKeys = true }.decodeFromString(File.serializer(), RepoFile.read("shared/test-vectors/ads/gate.json"))
        assertTrue(file.cases.size >= 20)
        for (c in file.cases) {
            assertEquals(c.id, AdsGate.Verdict(c.allowed, c.reason), AdsGate.canShow(c.placement, c.context))
        }
    }
}
