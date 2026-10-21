package app.pushly.feature.wakeflow

import app.pushly.engine.rep.PoseFrame
import app.pushly.engine.rep.PoseLandmark
import app.pushly.engine.rep.RejectReason
import app.pushly.engine.rep.RepEngine
import app.pushly.engine.rep.WorldPoint
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.int
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

    @Test
    fun recorderExportReplaysToTheSameCount() {
        val recorder = PoseRecorder()
        val model = RepSessionModel(RepSessionModel.Mode.Training, recorder = recorder)
        frames("synthetic-good-10-normal").forEach { model.ingest(it, 1280, 720) }
        val (id, json) = recorder.toJson(PoseRecorder.Label(10, tags = listOf("normal")), "test")
        assertTrue(id.startsWith("real-side-10-"))
        val v = Json.parseToJsonElement(json).jsonObject
        assertEquals(10, v["expected"]!!.jsonObject["counted"]!!.jsonPrimitive.int)
        val engine = RepEngine(1280.0, 720.0)
        v["frames"]!!.jsonArray.forEach { fr ->
            val o = fr.jsonObject
            engine.process(
                PoseFrame(
                    o["t"]!!.jsonPrimitive.long,
                    o["lm"]!!.jsonArray.map { p -> p.jsonArray.map { it.jsonPrimitive.double }.let { PoseLandmark(it[0], it[1], it[2], it[3], it[4]) } },
                    o["w"]!!.jsonArray.map { p -> p.jsonArray.map { it.jsonPrimitive.double }.let { WorldPoint(it[0], it[1], it[2]) } },
                ),
            )
        }
        assertEquals(10, engine.counted)
    }

    @Test
    fun cheatLabelExpectsZero() {
        val (_, json) = PoseRecorder().toJson(PoseRecorder.Label(6, tags = listOf("cheat")), "test")
        assertEquals(0, Json.parseToJsonElement(json).jsonObject["expected"]!!.jsonObject["counted"]!!.jsonPrimitive.int)
    }
}

/** Rep log + outbox (P4-05). Same cases as iOS RepSessionModelTests / SessionUploaderTests. */
class RepLogTest {
    @Test
    fun repLogFollowsTheContract() {
        val clock = app.pushly.core.common.FixedClock(1_792_472_520_000, 500_000)
        val model = RepSessionModel(RepSessionModel.Mode.Training, clock)
        var last: Long? = null
        frames("synthetic-good-10-normal").forEach { f ->
            last?.let { clock.advance(f.tMs - it) }
            last = f.tMs
            model.ingest(f, 1280, 720)
        }
        model.finish()
        val log = model.repLog("f0000000-0000-4000-8000-000000000001", "training", "0.1.0 (1)")
        assertEquals((1..10).toList(), log.reps.map { it.i })
        log.reps.forEachIndexed { k, r ->
            assertTrue(r.tStartMs <= r.tBottomMs && r.tBottomMs <= r.tEndMs)
            assertTrue("rep ${k + 1} duration", r.tEndMs - r.tStartMs >= 450)
            if (k > 0) assertTrue(r.tStartMs >= log.reps[k - 1].tEndMs)
        }
        assertEquals(500_000L, log.timing.monotonicStartMs)
        assertTrue("the 10 Hz feature trace goes with every log", log.featureTrace != null)
        assertEquals(0.0, log.suspicion.continuity, 0.0)
        assertTrue(log.timing.monotonicEndMs - log.timing.monotonicStartMs >= log.reps.last().tEndMs)
        val json = Json.parseToJsonElement(log.encode()).jsonObject
        assertEquals("android", json["platform"]!!.jsonPrimitive.content)
        assertTrue("null fields are left out", "serverAnchor" !in json["timing"]!!.jsonObject)
    }

    @Test
    fun decodesTheSharedRepLogVectors() {
        var dir: File? = File("").absoluteFile
        var file: File? = null
        while (dir != null && file == null) {
            File(dir, "shared/test-vectors/rep-log/cases.json").takeIf { it.exists() }?.let { file = it }
            dir = dir.parentFile
        }
        val cases = Json.parseToJsonElement(file!!.readText()).jsonObject["cases"]!!.jsonArray
        assertTrue(cases.size >= 15)
        cases.forEach { RepLog.JSON.decodeFromJsonElement(RepLog.serializer(), it.jsonObject["log"]!!) }
    }

    @Test
    fun timelineMarkers() {
        val tl = RepTimeline(1000, 0)
        tl.startSprint(4000)
        tl.startSprint(9000)
        tl.appendSet(100, 50)
        tl.end(20_000)
        assertEquals(3000L, tl.sprintStartMs)
        assertEquals(listOf(RepLog.SetSpan(100, 100)), tl.sets)
        assertEquals(20_000L, tl.monotonicEndMs)
    }
}

class SessionUploaderTest {
    private fun fixture(): String {
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            File(dir, "shared/contracts/fixtures/submit_rep_session_response.json").takeIf { it.exists() }?.let { return it.readText() }
            dir = dir.parentFile
        }
        error("fixture not found")
    }

    private fun log(id: String) = RepTimeline(0, 1_792_472_520_000).log(
        id, "training", null, "completed", 0, emptyMap(), null, null, "0.1.0 (1)", "test",
    )

    private fun tempDir(): File = kotlin.io.path.createTempDirectory("uploader").toFile()

    @Test
    fun uploadsAndKeepsTheServerResult() = kotlinx.coroutines.test.runTest {
        val dir = tempDir()
        val response = fixture()
        val uploader = SessionUploader(dir, backgroundScope, sleep = {})
        uploader.transport = { { _: String -> response } }
        uploader.enqueue(log("f0000000-0000-4000-8000-000000000001"))
        uploader.flush()
        testScheduler.advanceUntilIdle()
        assertTrue(uploader.pending.value.isEmpty())
        assertEquals("succeeded", uploader.results.value["f0000000-0000-4000-8000-000000000001"]?.wake?.status)
        val progress = uploader.results.value["f0000000-0000-4000-8000-000000000001"]?.progress
        assertEquals(40, progress?.xpGained)
        assertEquals(listOf("first_wake", "textbook"), progress?.newAchievements?.map { it.id })
        val reopened = SessionUploader(dir, backgroundScope, sleep = {})
        assertEquals(1, reopened.results.value["f0000000-0000-4000-8000-000000000001"]?.streak?.current)
    }

    @Test
    fun keepsTheQueueWhileOfflineAndDropsRefusedLogs() = kotlinx.coroutines.test.runTest {
        val dir = tempDir()
        val offline = SessionUploader(dir, backgroundScope, sleep = { kotlinx.coroutines.awaitCancellation() })
        offline.transport = { { _: String -> throw app.pushly.core.common.AppError(app.pushly.core.common.AppErrorCode.Network, "offline") } }
        offline.enqueue(log("f0000000-0000-4000-8000-000000000002"))
        offline.flush()
        assertTrue(offline.isPending("f0000000-0000-4000-8000-000000000002"))
        val refused = SessionUploader(dir, backgroundScope, sleep = {})
        refused.transport = { { _: String -> throw app.pushly.core.common.AppError(app.pushly.core.common.AppErrorCode.ValidationFailed, "bad") } }
        refused.flush()
        assertTrue(refused.pending.value.isEmpty())
    }
}

class LogSignerTest {
    /** JCA software key standing in for the Android Keystore in JVM tests. */
    private class SoftwareKey : DeviceKey {
        val pair: java.security.KeyPair = java.security.KeyPairGenerator.getInstance("EC").apply {
            initialize(java.security.spec.ECGenParameterSpec("secp256r1"))
        }.generateKeyPair()
        override val publicKeySpki: ByteArray get() = pair.public.encoded
        override fun sign(data: ByteArray): ByteArray = java.security.Signature.getInstance("SHA256withECDSA").run {
            initSign(pair.private)
            update(data)
            sign()
        }
    }

    @Test
    fun envelopeSignsTheExactLogBytes() = kotlinx.coroutines.test.runTest {
        val key = SoftwareKey()
        val registrations = ArrayList<String>()
        val signer = LogSigner(key, "0.1.0 (1)") { registrations += it; "d0000000-0000-4000-8000-000000000001" }
        val log = """{"sessionId":"f0000000-0000-4000-8000-000000000001","reps":[]}"""
        val body = Json.parseToJsonElement(signer.envelope(log)).jsonObject
        assertEquals("d0000000-0000-4000-8000-000000000001", body["deviceId"]!!.jsonPrimitive.content)
        assertEquals(log, body["log"]!!.jsonPrimitive.content)
        val ok = java.security.Signature.getInstance("SHA256withECDSA").run {
            initVerify(key.pair.public)
            update(log.encodeToByteArray())
            verify(java.util.Base64.getDecoder().decode(body["signature"]!!.jsonPrimitive.content))
        }
        assertTrue(ok)
        signer.envelope(log)
        assertEquals("the key is registered once per launch", 1, registrations.size)
        val reg = Json.parseToJsonElement(registrations[0]).jsonObject
        assertEquals("android", reg["platform"]!!.jsonPrimitive.content)
        assertEquals(java.util.Base64.getEncoder().encodeToString(key.publicKeySpki), reg["publicKey"]!!.jsonPrimitive.content)
    }

    @Test
    fun registrationFailureFallsBackToTheBareLog() = kotlinx.coroutines.test.runTest {
        val signer = LogSigner(SoftwareKey(), "0.1.0 (1)") { throw java.io.IOException("offline") }
        assertEquals("""{"reps":[]}""", signer.envelope("""{"reps":[]}"""))
    }
}
