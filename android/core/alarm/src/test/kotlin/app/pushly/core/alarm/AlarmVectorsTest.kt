package app.pushly.core.alarm

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/** Locates repository files from unit tests (Gradle runs tests with the module directory as working dir). */
private object RepoFile {
    fun dir(relative: String): File = find(relative)
    fun read(relative: String): String = find(relative).readText()

    private fun find(relative: String): File {
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            val candidate = File(dir, relative)
            if (candidate.exists()) return candidate
            dir = dir.parentFile
        }
        error("Not found from ${File("").absolutePath}: $relative")
    }
}

private val json = Json { ignoreUnknownKeys = true }

/** Runs the shared alarm vectors — iOS AlarmDomainTests runs the same files (CLAUDE.md §4.1). */
class AlarmVectorsTest {
    @Serializable data class OccJson(
        val occurrenceId: String,
        val alarmId: String,
        val localDate: String,
        val instant: String,
        val countsForChallenge: Boolean,
    )

    @Serializable data class OccExpected(val occurrences: List<OccJson>, val challengeByLocalDate: Map<String, String?>)

    @Serializable data class OccCase(
        val id: String,
        val timeZone: String,
        val from: String,
        val horizonDays: Int,
        val schedules: List<AlarmSchedule>,
        val expected: OccExpected,
    )

    @Serializable data class ValidationCase(val id: String, val schedule: AlarmSchedule, val expectedErrors: List<String>)

    @Serializable data class ValidationFile(val today: String, val cases: List<ValidationCase>)

    @Serializable data class PlanJson(
        val osAlarmId: String,
        val occurrenceId: String,
        val alarmId: String,
        val role: String,
        val fireAt: String,
        val countsForChallenge: Boolean,
    )

    @Serializable data class NextJson(val occurrenceId: String, val fireAt: String)

    @Serializable data class PlanExpected(val ios: List<PlanJson>, val androidNext: Map<String, NextJson?>)

    @Serializable data class PlanCase(
        val id: String,
        val timeZone: String,
        val from: String,
        val windowDays: Int,
        val nagCount: Int,
        val schedules: List<AlarmSchedule>,
        val expected: PlanExpected,
    )

    @Serializable data class IdCase(val occurrenceId: String, val role: String, val osAlarmId: String)

    @Serializable data class PlanFile(val osAlarmIds: List<IdCase>, val cases: List<PlanCase>)

    private fun iso(i: Instant) = i.toString()

    @Test
    fun occurrenceVectors() {
        val files = RepoFile.dir("shared/test-vectors/alarm-occurrences").listFiles { f -> f.extension == "json" }.orEmpty().sorted()
        assertTrue("expected ≥ 25 occurrence vectors", files.size >= 25)
        for (f in files) {
            val c = json.decodeFromString(OccCase.serializer(), f.readText())
            val zone = ZoneId.of(c.timeZone)
            val occ = AlarmOccurrences.all(c.schedules, Instant.parse(c.from), zone, c.horizonDays)
            val actual = occ.map { OccJson(it.occurrenceId, it.alarmId, it.localDate.toString(), iso(it.instant), it.countsForChallenge) }
            assertEquals(c.id, c.expected.occurrences, actual)
            val challenge = occ.map { it.localDate }.distinct().sorted()
                .associate { it.toString() to AlarmOccurrences.challengeOccurrence(it, occ)?.occurrenceId }
            assertEquals("${c.id} challenge", c.expected.challengeByLocalDate, challenge)
        }
    }

    @Test
    fun validationVectors() {
        val file = json.decodeFromString(ValidationFile.serializer(), RepoFile.read("shared/test-vectors/alarm-validation/cases.json"))
        val today = LocalDate.parse(file.today)
        for (c in file.cases) {
            assertEquals(c.id, c.expectedErrors.toSet(), AlarmValidation.errors(c.schedule, today))
        }
    }

    @Test
    fun planVectors() {
        val file = json.decodeFromString(PlanFile.serializer(), RepoFile.read("shared/test-vectors/alarm-plan/cases.json"))
        for (id in file.osAlarmIds) assertEquals(id.osAlarmId, AlarmPlan.osAlarmId(id.occurrenceId, id.role))
        for (c in file.cases) {
            val zone = ZoneId.of(c.timeZone)
            val from = Instant.parse(c.from)
            val ios = AlarmPlan.windowPlan(c.schedules, from, zone, c.windowDays, c.nagCount)
                .map { PlanJson(it.osAlarmId, it.occurrenceId, it.alarmId, it.role, iso(it.fireAt), it.countsForChallenge) }
            assertEquals("${c.id} window plan", c.expected.ios, ios)
            val next = AlarmPlan.nextPerAlarm(c.schedules, from, zone).mapValues { (_, o) -> o?.let { NextJson(it.occurrenceId, iso(it.instant)) } }
            assertEquals("${c.id} next", c.expected.androidNext, next)
        }
    }

    @Test
    fun scheduleRoundTripsThroughJson() {
        val s = AlarmSchedule.newDefault("a0000000-0000-4000-8000-000000000001")
        val back = json.decodeFromString(AlarmSchedule.serializer(), Json.encodeToString(AlarmSchedule.serializer(), s))
        assertEquals(s, back)
        assertTrue(AlarmValidation.errors(s, LocalDate.of(2026, 10, 19)).isEmpty())
    }

    @Test
    fun everyModeDefaultIsValid() {
        for (t in ModeType.entries) {
            val s = AlarmSchedule.newDefault("x").copy(mode = ChallengeMode.defaults(t))
            assertEquals(t.name, emptySet<String>(), AlarmValidation.errors(s, LocalDate.of(2026, 10, 19)))
        }
    }
}
