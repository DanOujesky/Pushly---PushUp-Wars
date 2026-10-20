package app.pushly.feature.wakeflow

import app.pushly.engine.rep.PoseFrame
import app.pushly.engine.rep.PoseLandmark
import app.pushly.engine.rep.RejectReason
import app.pushly.engine.rep.WorldPoint
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.util.zip.GZIPInputStream

private fun frames(name: String): List<PoseFrame> {
    var dir: File? = File("").absoluteFile
    var file: File? = null
    while (dir != null && file == null) {
        File(dir, "shared/test-vectors/pushup/$name.json.gz").takeIf { it.exists() }?.let { file = it }
        dir = dir.parentFile
    }
    val v = Json.parseToJsonElement(GZIPInputStream(file!!.inputStream()).readBytes().decodeToString()).jsonObject
    return v["frames"]!!.jsonArray.map { fr ->
        val o = fr.jsonObject
        PoseFrame(
            o["t"]!!.jsonPrimitive.long,
            o["lm"]!!.jsonArray.map { p -> p.jsonArray.map { it.jsonPrimitive.double }.let { PoseLandmark(it[0], it[1], it[2], it[3], it[4]) } },
            o["w"]!!.jsonArray.map { p -> p.jsonArray.map { it.jsonPrimitive.double }.let { WorldPoint(it[0], it[1], it[2]) } },
        )
    }
}

/** Same cases as iOS RepSessionModelTests. */
class RepSessionModelTest {
    @Test
    fun wakeSessionFinishesAtTarget() {
        var summary: RepSessionModel.Summary? = null
        val model = RepSessionModel(RepSessionModel.Mode.Wake(5), onFinished = { summary = it })
        frames("synthetic-good-10-normal").forEach { model.ingest(it, 1280, 720) }
        assertTrue(model.state.value.finished)
        assertEquals(5, model.state.value.counted)
        assertEquals(0, model.remaining())
        assertEquals(5, summary?.reps)
        assertTrue((summary?.averageQuality ?: 0) > 0)
    }

    @Test
    fun trainingCountsEverythingAndHintsBadForm() {
        val model = RepSessionModel(RepSessionModel.Mode.Training)
        frames("synthetic-mixed-session").forEach { model.ingest(it, 1280, 720) }
        assertFalse(model.state.value.finished)
        assertEquals(7, model.state.value.counted)
        assertEquals(2, model.summary().rejected[RejectReason.NotDeepEnough])
    }

    @Test
    fun cheatsCountNothing() {
        val model = RepSessionModel(RepSessionModel.Mode.Wake(3))
        frames("synthetic-cheat-arm-waving-lying").forEach { model.ingest(it, 1280, 720) }
        assertEquals(0, model.state.value.counted)
        assertFalse(model.state.value.finished)
    }
}
