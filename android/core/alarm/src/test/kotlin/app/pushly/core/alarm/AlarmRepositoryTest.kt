package app.pushly.core.alarm

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.ZoneId

class AlarmRepositoryTest {
    private val prague = ZoneId.of("Europe/Prague")
    private var now = Instant.parse("2026-10-19T12:00:00Z") // Monday 14:00 Prague
    private fun repo(store: DocumentStore = InMemoryDocumentStore()) = AlarmRepository(store) { now }

    @Test
    fun saveBumpsVersionPersistsAndQueues() {
        val store = InMemoryDocumentStore()
        val r = repo(store)
        val first = r.save(AlarmSchedule.newDefault("a"), prague) as SaveResult.Saved
        assertEquals(1, first.schedule.version)
        val second = r.save(first.schedule.copy(label = "  Rise  "), prague) as SaveResult.Saved
        assertEquals(2, second.schedule.version)
        assertEquals("Rise", second.schedule.label)
        assertEquals(listOf(OutboxEntry("a", OutboxEntry.UPSERT, 2, now.toString())), r.document.value.outbox)
        // A fresh repository on the same store sees the same alarms (survives app restart).
        assertEquals(r.alarms.value, repo(store).alarms.value)
    }

    @Test
    fun invalidScheduleIsRejected() {
        val bad = AlarmSchedule.newDefault("a").copy(mode = ChallengeMode(ModeType.RingUntilDone.wire, targetReps = 3))
        assertEquals(SaveResult.Invalid(setOf("mode.targetReps")), repo().save(bad, prague))
    }

    @Test
    fun atMostTwentyAlarms() {
        val r = repo()
        repeat(20) { r.save(AlarmSchedule.newDefault("a$it"), prague) }
        assertEquals(SaveResult.TooManyAlarms, r.save(AlarmSchedule.newDefault("x"), prague))
    }

    @Test
    fun skipNextAddsSkipOverrideForNextDate() {
        val r = repo()
        r.save(AlarmSchedule.newDefault("a"), prague)
        r.skipNext("a", prague)
        assertEquals(listOf(AlarmOverride("2026-10-20", skip = true)), r.alarm("a")?.overrides)
        assertEquals("2026-10-21", AlarmOccurrences.next(r.alarm("a")!!, now, prague)?.localDate.toString())
    }

    @Test
    fun pastOverridesAreDroppedOnSave() {
        val r = repo()
        val s = AlarmSchedule.newDefault("a").copy(overrides = listOf(AlarmOverride("2026-10-25", "07:00")))
        r.save(s, prague)
        now = Instant.parse("2026-10-27T12:00:00Z")
        val again = r.save(r.alarm("a")!!.copy(label = "x"), prague) as SaveResult.Saved
        assertTrue(again.schedule.overrides.isEmpty())
    }

    @Test
    fun deleteQueuesDeleteAndAckClearsOutbox() {
        val r = repo()
        r.save(AlarmSchedule.newDefault("a"), prague)
        r.delete("a")
        assertTrue(r.alarms.value.isEmpty())
        val entry = r.document.value.outbox.single()
        assertEquals(OutboxEntry.DELETE, entry.op)
        r.acknowledge(listOf(entry))
        assertTrue(r.document.value.outbox.isEmpty())
    }

    @Test
    fun corruptDocumentStartsEmptyInsteadOfCrashing() {
        assertTrue(repo(InMemoryDocumentStore("{not json")).alarms.value.isEmpty())
    }

    @Test
    fun ringStatesArePrunedAfterDeadline() {
        val r = repo()
        val s = AlarmSchedule.newDefault("a")
        val occ = Occurrence("a:2026-10-19", "a", java.time.LocalDate.of(2026, 10, 19), now, true)
        r.putRing(RingState.start(occ, s, now))
        now = now.plusSeconds(29 * 60)
        r.pruneRings()
        assertEquals(1, r.activeRings().size)
        now = now.plusSeconds(60)
        r.pruneRings()
        assertTrue(r.activeRings().isEmpty())
    }
}

class RingStateTest {
    private val t0 = Instant.parse("2026-10-20T04:30:00Z")
    private fun ring(mode: ChallengeMode, rangAt: Instant = t0) = RingState(
        occurrenceId = "a:2026-10-20", alarmId = "a", label = "", t0 = t0.toString(), rangAt = rangAt.toString(),
        mode = mode, countsForChallenge = true,
    )

    @Test
    fun escalationAddsRepsPerSnoozeUntilMax() {
        var r = ring(ChallengeMode.defaults(ModeType.Escalation, targetReps = 10))
        assertEquals(10, r.target)
        repeat(3) {
            assertTrue(r.canSnooze)
            r = r.snoozed(t0)
        }
        assertEquals(25, r.target)
        assertFalse(r.canSnooze)
        assertEquals("2026-10-20T04:35:00Z", r.snoozedUntil)
    }

    @Test
    fun beatTheClockStartsAtLateRing() {
        val m = ChallengeMode(ModeType.BeatTheClock.wire, targetReps = 10, windowSeconds = 60)
        assertEquals(Instant.parse("2026-10-20T04:31:00Z"), ring(m).beatTheClockEndsAt)
        assertEquals(Instant.parse("2026-10-20T04:31:20Z"), ring(m, t0.plusSeconds(20)).beatTheClockEndsAt)
        assertNull(ring(ChallengeMode.default()).beatTheClockEndsAt)
    }

    @Test
    fun setsTargetIsAllSets() {
        assertEquals(30, ring(ChallengeMode.defaults(ModeType.Sets)).target)
        assertFalse(ring(ChallengeMode.defaults(ModeType.Sets)).canSnooze)
    }

    @Test
    fun deadlineIsThirtyMinutes() {
        val r = ring(ChallengeMode.default())
        assertFalse(r.isExpired(t0.plusSeconds(29 * 60)))
        assertTrue(r.isExpired(t0.plusSeconds(30 * 60)))
    }
}

class AlarmHealthTest {
    @Test
    fun noAlarmsNoIssues() {
        assertEquals(emptyList<HealthIssue>(), AlarmHealth.issues(HealthInput(hasEnabledAlarms = false, exactAlarmAllowed = false)))
    }

    @Test
    fun criticalBeforeWarningsAndNotArmedOnlyWithoutPermissionCause() {
        val issues = AlarmHealth.issues(
            HealthInput(hasEnabledAlarms = true, exactAlarmAllowed = false, nextAlarmArmed = false, alarmVolumeZero = true),
        )
        assertEquals(listOf(HealthIssue.ExactAlarmMissing, HealthIssue.AlarmVolumeZero), issues)
        assertEquals(
            listOf(HealthIssue.NextAlarmNotArmed),
            AlarmHealth.issues(HealthInput(hasEnabledAlarms = true, exactAlarmAllowed = true, nextAlarmArmed = false)),
        )
    }
}

class AlarmSyncDiffTest {
    private fun d(key: String, sig: String) = AlarmSyncDiff.Desired(key, sig, Unit)

    @Test
    fun diffIsIdempotent() {
        val desired = listOf(d("a", "06:30"), d("b", "07:00"))
        val first = AlarmSyncDiff.compute(desired, mapOf("a" to "06:15", "z" to "05:00"))
        assertEquals(listOf("a", "z"), first.cancel)
        assertEquals(listOf("a", "b"), first.schedule.map { it.key })
        // After applying, the OS matches the plan: a second sync does nothing.
        assertTrue(AlarmSyncDiff.compute(desired, mapOf("a" to "06:30", "b" to "07:00")).isEmpty)
    }
}
