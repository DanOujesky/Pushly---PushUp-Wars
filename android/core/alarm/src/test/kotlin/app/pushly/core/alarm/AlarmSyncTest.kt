package app.pushly.core.alarm

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

/** Same cases as iOS AlarmSyncTests. */
class AlarmSyncTest {
    private fun repo() = AlarmRepository(InMemoryDocumentStore(), now = { Instant.parse("2026-10-20T08:00:00Z") })

    private fun alarm(id: String, target: Int = 20) = AlarmSchedule.newDefault(id).copy(
        weekly = WeeklyTimes(mon = "06:30"),
        mode = ChallengeMode(type = "ringUntilDone", targetReps = target),
    )

    @Test
    fun acceptedChangesLeaveOutboxAndAdoptServerVersion() {
        val r = repo()
        r.save(alarm("a"))
        val (changes, sent) = AlarmSync.changes(r.document.value)
        assertEquals("a", changes.single().alarm?.id)
        r.applySync(sent, AlarmSync.Response(listOf(AlarmSync.Result("a", "ok", version = 3)), listOf(alarm("a"))))
        assertTrue(r.document.value.outbox.isEmpty())
        assertEquals(3, r.alarm("a")?.version)
    }

    @Test
    fun editDuringSyncStaysQueued() {
        val r = repo()
        r.save(alarm("a"))
        val (_, sent) = AlarmSync.changes(r.document.value)
        r.save(alarm("a", target = 30))
        r.applySync(sent, AlarmSync.Response(listOf(AlarmSync.Result("a", "ok", version = 1))))
        assertEquals(1, r.document.value.outbox.size)
        assertEquals(30, r.alarm("a")?.mode?.targetReps)
    }

    @Test
    fun conflictTakesServerCopy() {
        val r = repo()
        r.save(alarm("a"))
        val (_, sent) = AlarmSync.changes(r.document.value)
        val server = alarm("a", target = 50).copy(version = 4)
        r.applySync(sent, AlarmSync.Response(listOf(AlarmSync.Result("a", "conflict", version = 4, server = server)), listOf(server)))
        assertEquals(50, r.alarm("a")?.mode?.targetReps)
        assertTrue(r.document.value.outbox.isEmpty())
    }

    @Test
    fun serverOnlyAlarmsAreRestoredButNotPendingDeletes() {
        val r = repo()
        r.save(alarm("a"))
        r.delete("a")
        val (changes, sent) = AlarmSync.changes(r.document.value)
        assertEquals("delete", changes.single().op)
        r.applySync(emptyList(), AlarmSync.Response(emptyList(), listOf(alarm("a"), alarm("b"))))
        assertNull(r.alarm("a"))
        assertNotNull(r.alarm("b"))
        r.applySync(sent, AlarmSync.Response(listOf(AlarmSync.Result("a", "ok")), listOf(alarm("b"))))
        assertTrue(r.document.value.outbox.isEmpty())
    }

    @Test
    fun wireFormatRoundTrips() {
        val json = """{"results":[{"id":"a","status":"invalid","errors":["mode.targetReps"]}],"alarms":[]}"""
        assertEquals(listOf("mode.targetReps"), AlarmSync.decode(json).results.single().errors)
        assertTrue(AlarmSync.encode(listOf(AlarmSync.Change("delete", id = "a", version = 2))).contains("\"op\":\"delete\""))
    }
}

/** Same cases as iOS EveningReminderTests. */
class EveningReminderTest {
    private val prague = java.time.ZoneId.of("Europe/Prague")

    @Test
    fun remindsTonightWhenAlarmTomorrowMorning() {
        assertEquals(
            Instant.parse("2026-10-20T19:00:00Z"),
            AlarmHealth.eveningReminder(true, Instant.parse("2026-10-21T04:30:00Z"), Instant.parse("2026-10-20T10:00:00Z"), prague),
        )
    }

    @Test
    fun noReminderWithoutCriticalIssue() {
        assertNull(AlarmHealth.eveningReminder(false, Instant.parse("2026-10-21T04:30:00Z"), Instant.parse("2026-10-20T10:00:00Z"), prague))
    }

    @Test
    fun afterNineMovesToTomorrowAndNeedsAlarmWithin24h() {
        val now = Instant.parse("2026-10-20T20:00:00Z")
        assertNull(AlarmHealth.eveningReminder(true, Instant.parse("2026-10-21T04:30:00Z"), now, prague))
        assertEquals(Instant.parse("2026-10-21T19:00:00Z"), AlarmHealth.eveningReminder(true, Instant.parse("2026-10-22T04:30:00Z"), now, prague))
    }
}
