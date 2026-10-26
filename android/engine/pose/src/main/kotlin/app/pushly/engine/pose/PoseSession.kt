package app.pushly.engine.pose

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Matrix
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.util.Size
import android.view.Surface
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import app.pushly.core.common.PLog
import app.pushly.engine.rep.PoseFrame
import app.pushly.engine.rep.PoseLandmark
import app.pushly.engine.rep.WorldPoint
import app.pushly.engine.rep.generated.PushupSpecV2
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarkerResult
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.sqrt

/** What the camera session reports besides pose frames. */
data class PoseSessionStatus(
    val fps: Double = 0.0,
    val model: PoseModel = PoseModel.Full,
    val tooDark: Boolean = false,
    val imageWidth: Int = 720,
    val imageHeight: Int = 1280,
    val personVisible: Boolean = false,
    /** A second person is in the frame (doc 06 §2.2) — counting pauses until they leave. */
    val multiplePeople: Boolean = false,
)

enum class PoseModel(val asset: String) {
    Full("pose_landmarker_full.task"),
    Lite("pose_landmarker_lite.task"),
}

/**
 * CameraX (front camera, ~1280×720, latest frame only) → MediaPipe Pose Landmarker (LIVE_STREAM, 1 pose, GPU with CPU
 * fallback) → [PoseFrame] (doc 05 §2–3). Frames are rotated upright and NOT mirrored: the engine always gets
 * un-mirrored coordinates (the PreviewView mirrors only what the user sees). Device motion feeds the anti-cheat check
 * (doc 06 §2.1). Switches to the lite model when too slow or hot (doc 05 §7). Callbacks run on the main thread.
 */
class PoseSession(
    private val context: Context,
    private val onFrame: (PoseFrame, Int, Int) -> Unit,
    private val onStatus: (PoseSessionStatus) -> Unit,
) {
    private val main = Handler(Looper.getMainLooper())
    private val analysisExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val lock = Any()
    private var landmarker: PoseLandmarker? = null

    /** Image-mode lite landmarker with 2 poses, run on every 30th frame to spot a second person (doc 06 §2.2). */
    private var peopleChecker: PoseLandmarker? = null
    private var model = PoseModel.Full
    @Volatile private var status = PoseSessionStatus()
    private val frameTimes = ArrayDeque<Long>()
    private var slowSince: Long? = null
    private var darkSince: Long? = null
    private var frameCounter = 0
    private var lastTimestamp = -1L
    private val motion = MotionMonitor(context)
    private var provider: ProcessCameraProvider? = null

    /** Second consumer of the same frames (battle video, doc 07 §5: never open the camera twice). Upright, un-mirrored. */
    @Volatile var videoTap: ((Bitmap) -> Unit)? = null

    /** Loads the model ahead of time (e.g. while the ring screen is shown) — doc 05 §7 pre-warm. */
    fun prewarm() {
        synchronized(lock) {
            if (landmarker == null) landmarker = create(preferredModel())
            if (peopleChecker == null) peopleChecker = createPeopleChecker()
        }
    }

    fun start(owner: LifecycleOwner, preview: Preview.SurfaceProvider, front: Boolean = true) {
        analysisExecutor.execute { prewarm() }
        motion.start()
        val future = ProcessCameraProvider.getInstance(context)
        future.addListener({
            val p = runCatching { future.get() }.getOrElse {
                PLog.error(PLog.Category.Camera) { "Camera provider unavailable: ${it.message}" }
                return@addListener
            }
            provider = p
            val selector = ResolutionSelector.Builder()
                .setResolutionStrategy(ResolutionStrategy(Size(1280, 720), ResolutionStrategy.FALLBACK_RULE_CLOSEST_LOWER_THEN_HIGHER))
                .build()
            val previewUseCase = Preview.Builder().setResolutionSelector(selector).build().also { it.setSurfaceProvider(preview) }
            val analysis = ImageAnalysis.Builder()
                .setResolutionSelector(selector)
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                .build()
            analysis.setAnalyzer(analysisExecutor, ::analyze)
            // The app is portrait-only (D-079): frames are always portrait, however the phone is held.
            analysis.targetRotation = Surface.ROTATION_0
            val camera = if (front) CameraSelector.DEFAULT_FRONT_CAMERA else CameraSelector.DEFAULT_BACK_CAMERA
            try {
                p.unbindAll()
                p.bindToLifecycle(owner, camera, previewUseCase, analysis)
            } catch (e: IllegalArgumentException) {
                PLog.error(PLog.Category.Camera) { "Camera bind failed: ${e.message}" }
            }
        }, ContextCompat.getMainExecutor(context))
    }

    fun stop() {
        provider?.unbindAll()
        motion.stop()
        analysisExecutor.execute {
            synchronized(lock) {
                landmarker?.close()
                landmarker = null
                peopleChecker?.close()
                peopleChecker = null
            }
        }
    }

    // ------------------------------------------------------------------ model

    private fun preferredModel(): PoseModel = if (isHot()) PoseModel.Lite else PoseModel.Full

    private fun isHot(): Boolean =
        context.getSystemService(PowerManager::class.java)?.currentThermalStatus?.let { it >= PowerManager.THERMAL_STATUS_SEVERE } ?: false

    private fun create(m: PoseModel): PoseLandmarker? {
        model = m
        status = status.copy(model = m)
        for (delegate in listOf(Delegate.GPU, Delegate.CPU)) {
            try {
                val options = PoseLandmarker.PoseLandmarkerOptions.builder()
                    .setBaseOptions(BaseOptions.builder().setModelAssetPath(m.asset).setDelegate(delegate).build())
                    .setRunningMode(RunningMode.LIVE_STREAM)
                    .setNumPoses(1)
                    .setMinPoseDetectionConfidence(0.5f)
                    .setMinPosePresenceConfidence(0.5f)
                    .setMinTrackingConfidence(0.5f)
                    .setOutputSegmentationMasks(false)
                    .setResultListener(::onResult)
                    .setErrorListener { e -> PLog.warning(PLog.Category.Pose) { "Pose error: ${e.message}" } }
                    .build()
                return PoseLandmarker.createFromOptions(context, options)
            } catch (e: RuntimeException) {
                PLog.warning(PLog.Category.Pose) { "Pose landmarker on $delegate failed: ${e.message}" }
            }
        }
        return null
    }

    private fun createPeopleChecker(): PoseLandmarker? = try {
        val options = PoseLandmarker.PoseLandmarkerOptions.builder()
            .setBaseOptions(BaseOptions.builder().setModelAssetPath(PoseModel.Lite.asset).setDelegate(Delegate.CPU).build())
            .setRunningMode(RunningMode.IMAGE)
            .setNumPoses(2)
            .setMinPoseDetectionConfidence(0.5f)
            .setMinPosePresenceConfidence(0.5f)
            .setOutputSegmentationMasks(false)
            .build()
        PoseLandmarker.createFromOptions(context, options)
    } catch (e: RuntimeException) {
        PLog.warning(PLog.Category.Pose) { "People checker unavailable: ${e.message}" }
        null
    }

    /** True when the checker sees two people with a solid second pose. */
    private fun checkPeople(bitmap: Bitmap) {
        val checker = synchronized(lock) { peopleChecker } ?: return
        val result = runCatching { checker.detect(BitmapImageBuilder(bitmap).build()) }.getOrNull() ?: return
        val poses = result.landmarks()
        val two = poses.size >= 2 && poses[1].let { second ->
            second.sumOf { it.presence().orElse(0f).toDouble() } / maxOf(second.size, 1) >= 0.5
        }
        if (two != status.multiplePeople) {
            status = status.copy(multiplePeople = two)
            publish()
        }
    }

    private fun switchToLite(reason: String) {
        synchronized(lock) {
            if (model != PoseModel.Full) return
            PLog.info(PLog.Category.Pose) { "Switching to the lite pose model: $reason" }
            landmarker?.close()
            landmarker = create(PoseModel.Lite)
            frameTimes.clear()
        }
    }

    // ------------------------------------------------------------------ frames

    private fun analyze(image: ImageProxy) {
        try {
            val ts = image.imageInfo.timestamp / 1_000_000
            if (ts <= lastTimestamp) return
            lastTimestamp = ts
            val rotation = image.imageInfo.rotationDegrees
            val raw = image.toBitmap()
            val bitmap = if (rotation != 0) {
                Bitmap.createBitmap(raw, 0, 0, raw.width, raw.height, Matrix().apply { postRotate(rotation.toFloat()) }, false)
            } else {
                raw
            }
            status = status.copy(imageWidth = bitmap.width, imageHeight = bitmap.height)
            videoTap?.invoke(bitmap)
            frameCounter += 1
            if (frameCounter % 10 == 0) checkLight(bitmap, ts)
            if (frameCounter % 30 == 0) checkPeople(bitmap)
            if (isHot()) switchToLite("thermal state")
            val lm = synchronized(lock) { landmarker } ?: return
            lm.detectAsync(BitmapImageBuilder(bitmap).build(), ts)
        } catch (e: RuntimeException) {
            PLog.warning(PLog.Category.Camera) { "Frame skipped: ${e.message}" }
        } finally {
            image.close()
        }
    }

    private fun checkLight(bitmap: Bitmap, ts: Long) {
        var sum = 0.0
        var n = 0
        val stepX = maxOf(bitmap.width / 8, 1)
        val stepY = maxOf(bitmap.height / 8, 1)
        var y = bitmap.height / 16
        while (y < bitmap.height) {
            var x = bitmap.width / 16
            while (x < bitmap.width) {
                val c = bitmap.getPixel(x, y)
                sum += 0.299 * ((c shr 16) and 0xFF) + 0.587 * ((c shr 8) and 0xFF) + 0.114 * (c and 0xFF)
                n += 1
                x += stepX
            }
            y += stepY
        }
        val luma = if (n > 0) sum / n / 255.0 else 1.0
        darkSince = if (luma < 0.12) darkSince ?: ts else null
        val dark = darkSince?.let { ts - it >= 2000 } ?: false
        if (dark != status.tooDark) {
            status = status.copy(tooDark = dark)
            publish()
        }
    }

    private fun onResult(result: PoseLandmarkerResult, input: com.google.mediapipe.framework.image.MPImage) {
        val ts = result.timestampMs()
        trackFps(ts)
        val lms = result.landmarks().firstOrNull()
        val world = result.worldLandmarks().firstOrNull()
        if (lms == null || world == null || lms.size != 33 || world.size != 33) {
            if (status.personVisible) {
                status = status.copy(personVisible = false)
                publish()
            }
            return
        }
        val frame = PoseFrame(
            tMs = ts,
            landmarks = lms.map {
                PoseLandmark(
                    it.x().toDouble(), it.y().toDouble(), it.z().toDouble(),
                    it.visibility().orElse(0f).toDouble(), it.presence().orElse(0f).toDouble(),
                )
            },
            world = world.map { WorldPoint(it.x().toDouble(), it.y().toDouble(), it.z().toDouble()) },
            motion = motion.rms(),
        )
        if (!status.personVisible) {
            status = status.copy(personVisible = true)
            publish()
        }
        val w = input.width
        val h = input.height
        main.post { onFrame(frame, w, h) }
    }

    private fun trackFps(ts: Long) {
        frameTimes.addLast(ts)
        if (frameTimes.size > 30) frameTimes.removeFirst()
        if (frameTimes.size < 10) return
        val span = frameTimes.last() - frameTimes.first()
        if (span <= 0) return
        val fps = (frameTimes.size - 1) * 1000.0 / span
        status = status.copy(fps = fps)
        // Lite model if the full one stays under 15 fps for 3 s (doc 05 §3).
        if (fps < PushupSpecV2.Performance.LITE_MODEL_BELOW_FPS) {
            val since = slowSince ?: ts.also { slowSince = it }
            if (ts - since >= PushupSpecV2.Performance.LITE_MODEL_AFTER_MS) switchToLite("fps ${fps.toInt()}")
        } else {
            slowSince = null
        }
        if (frameTimes.size % 15 == 0) publish()
    }

    private fun publish() {
        val s = status
        main.post { onStatus(s) }
    }
}

/** Device motion RMS (linear acceleration, in g) over the last second at ~50 Hz (doc 06 §2.1). */
internal class MotionMonitor(context: Context) : SensorEventListener {
    private val sensors = context.getSystemService(SensorManager::class.java)
    private val samples = ArrayDeque<Double>()

    fun start() {
        val s = sensors?.getDefaultSensor(Sensor.TYPE_LINEAR_ACCELERATION) ?: return
        sensors.registerListener(this, s, 20_000)
    }

    fun stop() {
        sensors?.unregisterListener(this)
    }

    @Synchronized
    override fun onSensorChanged(event: SensorEvent) {
        val g = SensorManager.GRAVITY_EARTH
        val x = event.values[0] / g
        val y = event.values[1] / g
        val z = event.values[2] / g
        samples.addLast((x * x + y * y + z * z).toDouble())
        if (samples.size > 50) samples.removeFirst()
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    @Synchronized
    fun rms(): Double? = if (samples.isEmpty()) null else sqrt(samples.sum() / samples.size)
}

