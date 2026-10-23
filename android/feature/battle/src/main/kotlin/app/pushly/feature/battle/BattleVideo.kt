package app.pushly.feature.battle

import android.content.Context
import android.graphics.Bitmap
import android.os.SystemClock
import app.pushly.core.common.BattleService
import app.pushly.core.common.PLog
import app.pushly.feature.wakeflow.RepSessionModel
import io.livekit.android.LiveKit
import io.livekit.android.events.RoomEvent
import io.livekit.android.events.collect
import io.livekit.android.room.Room
import io.livekit.android.room.track.LocalVideoTrack
import io.livekit.android.room.track.LocalVideoTrackOptions
import io.livekit.android.room.track.VideoCaptureParameter
import io.livekit.android.room.track.VideoTrack
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import livekit.org.webrtc.CapturerObserver
import livekit.org.webrtc.JavaI420Buffer
import livekit.org.webrtc.SurfaceTextureHelper
import livekit.org.webrtc.VideoCapturer
import livekit.org.webrtc.VideoFrame

/**
 * Battle video (doc 07 §5, same as iOS BattleVideo): joins the battle's LiveKit room, publishes my camera (the same
 * frames MediaPipe gets — the camera is never opened twice) and exposes the opponent's track. Camera only, no
 * microphone; nothing is recorded. Without a token (video not configured, ghost / bot battles) the battle simply runs
 * without video.
 */
class BattleVideo(private val context: Context) {
    enum class State { Off, Connecting, Connected, Unavailable }

    private val _state = MutableStateFlow(State.Off)
    val state: StateFlow<State> = _state.asStateFlow()
    private val _remote = MutableStateFlow<VideoTrack?>(null)

    /** The opponent's camera, once subscribed. */
    val remoteTrack: StateFlow<VideoTrack?> = _remote.asStateFlow()
    private val _cameraOn = MutableStateFlow(true)

    /** My camera goes out (toggle in the battle HUD). Default on; off keeps watching the opponent. */
    val cameraOn: StateFlow<Boolean> = _cameraOn.asStateFlow()

    var room: Room? = null
        private set
    private var localTrack: LocalVideoTrack? = null
    private var events: Job? = null
    private var reps: RepSessionModel? = null
    private val capturer = FrameCapturer()

    @Serializable private data class Grant(val url: String, val token: String)

    suspend fun start(battleId: String, service: BattleService, reps: RepSessionModel, scope: CoroutineScope) {
        if (_state.value != State.Off) return
        this.reps = reps
        _state.value = State.Connecting
        val grant = try {
            BattleJson.decodeFromString(Grant.serializer(), service.battleVideoToken(battleId))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            _state.value = State.Unavailable
            return
        }
        val r = LiveKit.create(context.applicationContext)
        room = r
        events = scope.launch {
            r.events.collect { e ->
                when (e) {
                    is RoomEvent.TrackSubscribed -> (e.track as? VideoTrack)?.let { _remote.value = it }
                    is RoomEvent.TrackUnsubscribed -> if (e.track is VideoTrack) _remote.value = null
                    else -> Unit
                }
            }
        }
        try {
            r.connect(grant.url, grant.token)
            _state.value = State.Connected
            if (_cameraOn.value) publish()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            PLog.warning(PLog.Category.Battle) { "Battle video unavailable: ${e.message}" }
            _state.value = State.Unavailable
        }
    }

    suspend fun toggleCamera() {
        _cameraOn.value = !_cameraOn.value
        if (_state.value != State.Connected) return
        if (_cameraOn.value) publish() else unpublish()
    }

    fun stop() {
        reps?.videoTap = null
        events?.cancel()
        localTrack?.let { room?.localParticipant?.unpublishTrack(it) }
        localTrack = null
        room?.disconnect()
        room?.release()
        room = null
        _remote.value = null
        _state.value = State.Off
        capturer.shutdown()
    }

    private suspend fun publish() {
        val r = room ?: return
        if (localTrack != null) return
        val track = r.localParticipant.createVideoTrack(
            name = "camera",
            capturer = capturer,
            options = LocalVideoTrackOptions(captureParams = VideoCaptureParameter(540, 960, 15)),
        )
        track.startCapture()
        reps?.videoTap = capturer::offer
        // LiveKit needs first frames to know the dimensions before publishing.
        delay(400)
        try {
            r.localParticipant.publishVideoTrack(track)
            localTrack = track
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            PLog.warning(PLog.Category.Battle) { "Publishing battle video failed: ${e.message}" }
            reps?.videoTap = null
        }
    }

    private fun unpublish() {
        reps?.videoTap = null
        localTrack?.let { room?.localParticipant?.unpublishTrack(it) }
        localTrack = null
    }
}

/**
 * Feeds our own camera bitmaps into WebRTC: every other frame (≈ 15 fps), scaled to 540 px wide, converted to I420 on
 * its own thread (dropped while busy) so pose analysis keeps priority (doc 07 §5).
 */
private class FrameCapturer : VideoCapturer {
    @Volatile private var observer: CapturerObserver? = null
    private val worker: ExecutorService = Executors.newSingleThreadExecutor()
    private val busy = AtomicBoolean(false)
    private var n = 0

    override fun initialize(helper: SurfaceTextureHelper?, context: Context?, observer: CapturerObserver?) {
        this.observer = observer
    }

    override fun startCapture(width: Int, height: Int, framerate: Int) {
        observer?.onCapturerStarted(true)
    }

    override fun stopCapture() {
        observer?.onCapturerStopped()
    }

    override fun changeCaptureFormat(width: Int, height: Int, framerate: Int) = Unit

    override fun dispose() = Unit

    override fun isScreencast(): Boolean = false

    /** Called on the camera thread with the upright frame MediaPipe also gets (not modified, not kept). */
    fun offer(bitmap: Bitmap) {
        n += 1
        if (n % 2 != 0 || observer == null || !busy.compareAndSet(false, true)) return
        val w = 540
        val h = (bitmap.height * w / bitmap.width.toFloat()).toInt() and 1.inv()
        val scaled = Bitmap.createScaledBitmap(bitmap, w, h, true)
        val ts = TimeUnit.MILLISECONDS.toNanos(SystemClock.elapsedRealtime())
        worker.execute {
            try {
                val frame = VideoFrame(toI420(scaled), 0, ts)
                observer?.onFrameCaptured(frame)
                frame.release()
            } finally {
                scaled.recycle()
                busy.set(false)
            }
        }
    }

    fun shutdown() {
        worker.shutdown()
    }

    private fun toI420(bmp: Bitmap): JavaI420Buffer {
        val w = bmp.width and 1.inv()
        val h = bmp.height and 1.inv()
        val px = IntArray(w * h)
        bmp.getPixels(px, 0, w, 0, 0, w, h)
        val buf = JavaI420Buffer.allocate(w, h)
        val y = buf.dataY
        val u = buf.dataU
        val v = buf.dataV
        val sy = buf.strideY
        val su = buf.strideU
        val sv = buf.strideV
        for (j in 0 until h) {
            for (i in 0 until w) {
                val c = px[j * w + i]
                val r = (c shr 16) and 0xff
                val g = (c shr 8) and 0xff
                val b = c and 0xff
                y.put(j * sy + i, (((66 * r + 129 * g + 25 * b + 128) shr 8) + 16).toByte())
                if (j % 2 == 0 && i % 2 == 0) {
                    u.put((j / 2) * su + i / 2, (((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128).toByte())
                    v.put((j / 2) * sv + i / 2, (((112 * r - 94 * g - 18 * b + 128) shr 8) + 128).toByte())
                }
            }
        }
        return buf
    }
}
