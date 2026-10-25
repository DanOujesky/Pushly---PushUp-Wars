package app.pushly.feature.wakeflow

import app.pushly.feature.wakeflow.generated.WorkoutPresets
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.int
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import kotlinx.serialization.json.longOrNull
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Workouts (D-069): runner, validation and presets against shared/test-vectors/workouts/runner.json. */
class WorkoutTest {
    private val json = Json { ignoreUnknownKeys = true }

    private fun vectors(): JsonObject {
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            val f = File(dir, "shared/test-vectors/workouts/runner.json")
            if (f.exists()) return Json.parseToJsonElement(f.readText()).jsonObject
            dir = dir.parentFile
        }
        error("runner.json not found")
    }

    private fun event(e: JsonObject): WorkoutRunner.Event {
        val t = e.getValue("t").jsonPrimitive.long
        return when (val type = e.getValue("type").jsonPrimitive.content) {
            "setStarted" -> WorkoutRunner.Event.SetStarted(e.getValue("set").jsonPrimitive.int, t)
            "setEnded" -> WorkoutRunner.Event.SetEnded(e.getValue("set").jsonPrimitive.int, e.getValue("reps").jsonPrimitive.int,
                e.getValue("completed").jsonPrimitive.boolean, t)
            "restStarted" -> WorkoutRunner.Event.RestStarted(e.getValue("next").jsonPrimitive.int, e.getValue("until").jsonPrimitive.long, t)
            "done" -> WorkoutRunner.Event.Done(t)
            else -> error("unknown event $type")
        }
    }

    private fun JsonElement.longOrNullValue(): Long? = if (this is JsonNull) null else jsonPrimitive.longOrNull

    @Test
    fun runnerMatchesTheSharedVectors() {
        val v = vectors()
        val cases = v.getValue("runner").jsonArray
        assertTrue(cases.size >= 10)
        for (c in cases.map { it.jsonObject }) {
            val id = c.getValue("id").jsonPrimitive.content
            val w = json.decodeFromJsonElement(Workout.serializer(), c.getValue("workout"))
            val r = WorkoutRunner(w)
            for (s in c.getValue("steps").jsonArray.map { it.jsonObject }) {
                val t = s.getValue("t").jsonPrimitive.long
                when (val op = s.getValue("op").jsonPrimitive.content) {
                    "start" -> r.start(t)
                    "rep" -> r.rep(t)
                    "tick" -> r.tick(t)
                    "endSet" -> r.endSet(t)
                    "skipRest" -> r.skipRest(t)
                    "finish" -> r.finish(t)
                    else -> error("unknown op $op")
                }
            }
            assertEquals(id, c.getValue("events").jsonArray.map { event(it.jsonObject) }, r.events)
            val results = c.getValue("results").jsonArray.map {
                val o = it.jsonObject
                WorkoutRunner.SetResult(o.getValue("reps").jsonPrimitive.int, o.getValue("target").jsonPrimitive.int,
                    o.getValue("completed").jsonPrimitive.boolean)
            }
            assertEquals(id, results, r.results)
            val f = c.getValue("final").jsonObject
            val snap = r.snapshot(c.getValue("finalT").jsonPrimitive.long)
            assertEquals(id, f.getValue("phase").jsonPrimitive.content, snap.phase.name.lowercase())
            assertEquals(id, f.getValue("index").jsonPrimitive.int, snap.index)
            assertEquals(id, f.getValue("setReps").jsonPrimitive.int, snap.setReps)
            assertEquals(id, f.getValue("total").jsonPrimitive.int, snap.total)
            assertEquals(id, f.getValue("msLeft").longOrNullValue(), snap.msLeft)
        }
    }

    @Test
    fun validationMatchesTheReference() {
        for (c in vectors().getValue("validation").jsonArray.map { it.jsonObject }) {
            val o = c.getValue("workout").jsonObject
            val sets = o.getValue("sets").jsonArray.map { json.decodeFromJsonElement(WorkoutSet.serializer(), it) }
            val w = Workout(name = o.getValue("name").jsonPrimitive.content, everyS = o["everyS"]?.jsonPrimitive?.intOrNull, sets = sets)
            val expected = c.getValue("expectedErrors").jsonArray.map { it.jsonPrimitive.content }
            assertEquals(c.getValue("id").jsonPrimitive.content, expected, w.validationErrors)
        }
    }

    @Test
    fun presetsAreValidAndMatchThePlannedTotals() {
        val planned = vectors().getValue("plannedReps").jsonArray.map { it.jsonObject }
        assertEquals(planned.map { it.getValue("id").jsonPrimitive.content }, WorkoutPresets.all.map { it.id })
        WorkoutPresets.all.zip(planned).forEach { (p, e) ->
            val w = Workout(id = p.id, name = p.id, everyS = p.everyS, sets = p.sets)
            assertEquals(p.id, emptyList<String>(), w.validationErrors)
            assertEquals(p.id, e["planned"]?.let { if (it is JsonNull) null else it.jsonPrimitive.int }, w.plannedReps)
        }
    }

    @Test
    fun customWorkoutsRoundTripThroughJson() {
        val w = Workout(name = "Mine", description = "", everyS = 60, sets = listOf(WorkoutSet(SetKind.REPS, 12, 0)))
        val list = listOf(w, Workout(name = "Max", sets = listOf(WorkoutSet(SetKind.AMRAP, 0, 90), WorkoutSet(SetKind.TIMED, 30, 0))))
        val text = WorkoutStore.JSON.encodeToString(kotlinx.serialization.builtins.ListSerializer(Workout.serializer()), list)
        assertTrue(text.contains("\"amrap\""))
        assertEquals(list, WorkoutStore.JSON.decodeFromString(kotlinx.serialization.builtins.ListSerializer(Workout.serializer()), text))
    }
}
