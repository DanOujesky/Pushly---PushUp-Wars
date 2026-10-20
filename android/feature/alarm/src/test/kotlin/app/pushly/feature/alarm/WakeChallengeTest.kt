package app.pushly.feature.alarm

import app.pushly.core.alarm.ChallengeMode
import app.pushly.core.alarm.RingState
import app.pushly.core.common.FixedClock
import app.pushly.engine.rep.PoseFrame
import app.pushly.engine.rep.PoseLandmark
import app.pushly.engine.rep.WorldPoint
import app.pushly.feature.wakeflow.RepSessionModel
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.time.Instant
import java.util.zip.GZIPInputStream

/** Wake challenge flow with real engine output (synthetic vectors). Same cases as iOS WakeChallengeModelTests. */
class WakeChallengeTest {
    private val t0 = 1_792_472_400_000L // 2026-10-20T05:00:00Z

    private fun frames(name: String): List<PoseFrame> {
        var dir: File? = File("").absoluteFile
        var file: File? = null
        while (dir != null && file == null) {
            File(dir, "shared/test-vectors/pushup/$name.json.gz").takeIf { it.exists() }?.let { file = it }
            dir = dir.parentFile
        }
        val v = Json.parseToJsonElement(GZIPInputStream(requireNotNull(file).inputStream()).readBytes().decodeToString()).jsonObject
        return requireNotNull(v["frames"]).jsonArray.map { fr ->
            val o = fr.jsonObject
            PoseFrame(
                requireNotNull(o["t"]).jsonPrimitive.long,
                requireNotNull(o["lm"]).jsonArray.map { p -> p.jsonArray.map { it.jsonPrimitive.double }.let { PoseLandmark(it[0], it[1], it[2], it[3], it[4]) } },
                requireNotNull(o["w"]).jsonArray.map { p -> p.jsonArray.map { it.jsonPrimitive.double }.let { WorldPoint(it[0], it[1], it[2]) } },
            )
        }
    }

    private fun ring(mode: ChallengeMode) = RingState(
        occurrenceId = "a0000000-0000-4000-8000-000000000001:2026-10-20",
        alarmId = "a0000000-0000-4000-8000-000000000001",
        label = "Up",
        t0 = Instant.ofEpochMilli(t0).toString(),
        rangAt = Instant.ofEpochMilli(t0).toString(),
        mode = mode,
        countsForChallenge = true,
    )

    private fun run(challenge: WakeChallenge, clock: FixedClock, name: String) {
        var last: Long? = null
        for (f in frames(name)) {
            last?.let { clock.advance(f.tMs - it) }
            last = f.tMs
            challenge.reps.ingest(f, 1280, 720)
            challenge.tick()
        }
    }

    @Test
    fun ringUntilDoneSucceedsAtTarget() {
        val clock = FixedClock(t0 + 60_000, 0)
        val mode = ChallengeMode("ringUntilDone", targetReps = 5)
        var over: Boolean? = null
        val challenge = WakeChallenge(ring(mode), null, onOver = { over = it },
            model = RepSessionModel(RepSessionModel.Mode.Wake(5), clock))
        run(challenge, clock, "synthetic-good-10-normal")
        assertEquals(true, over)
        assertEquals("succeeded", challenge.decision.value?.status)
        assertEquals(WakeChallenge.Phase.Done, challenge.phase.value)
    }

    @Test
    fun cheatingNeverFinishesAndGivingUpFails() {
        val clock = FixedClock(t0 + 60_000, 0)
        val mode = ChallengeMode("ringUntilDone", targetReps = 5)
        val challenge = WakeChallenge(ring(mode), null, model = RepSessionModel(RepSessionModel.Mode.Wake(5), clock))
        run(challenge, clock, "synthetic-cheat-arm-waving-lying")
        assertEquals(null, challenge.decision.value)
        challenge.giveUp()
        assertEquals("failed", challenge.decision.value?.status)
    }

    @Test
    fun setsSplitsTheRepsAndStartsARest() {
        val clock = FixedClock(t0 + 60_000, 0)
        val mode = ChallengeMode("sets", sets = 2, repsPerSet = 4, restSeconds = 600)
        val challenge = WakeChallenge(ring(mode), null, model = RepSessionModel(RepSessionModel.Mode.Open, clock))
        run(challenge, clock, "synthetic-good-10-normal")
        // 4 reps → set 1 done → rest; the 5th rep starts set 2; 8 reps → both sets done.
        assertEquals("succeeded", challenge.decision.value?.status)
        val sets = requireNotNull(challenge.reps.timeline).sets
        assertEquals(2, sets.size)
        assertTrue(sets[1].startMs > sets[0].endMs)
    }

    @Test
    fun deadlineExpiresTheChallenge() {
        val clock = FixedClock(t0 + 29 * 60_000L, 0)
        val challenge = WakeChallenge(ring(ChallengeMode("ringUntilDone", targetReps = 20)), null,
            model = RepSessionModel(RepSessionModel.Mode.Wake(20), clock))
        challenge.reps.restartClock() // camera opened 1 min before the deadline
        challenge.tick()
        assertEquals(null, challenge.decision.value)
        clock.advance(2 * 60_000L)
        challenge.tick()
        assertEquals("failed", challenge.decision.value?.status)
        assertEquals("expired", challenge.reps.outcome)
    }
}
