package app.pushly.feature.alarm

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import app.pushly.core.alarm.AlarmOccurrences
import app.pushly.core.alarm.AlarmSchedule
import app.pushly.core.alarm.AlarmSounds
import app.pushly.core.alarm.Occurrence
import app.pushly.core.alarm.RingState
import app.pushly.core.common.PLog
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.time.Instant
import java.time.ZoneId

/**
 * Rings the alarm (doc 04 §6.3): foreground service, alarm-stream sound with a volume ramp, vibration, wake lock and
 * the full-screen ring notification. There is no "stop": it ends on completion, give-up, an escalation snooze or the
 * deadline (T0 + 30 min). Hardware volume keys lower the volume but never stop it.
 */
class AlarmRingService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var player: MediaPlayer? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var vibrator: Vibrator? = null
    private var currentVolume = 0f
    private var targetVolume = 1f
    private val system by lazy { AlarmSystem.get(this) }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> start(intent)
            ACTION_RESUME -> resume()
            ACTION_QUIET -> setLevel(QUIET_VOLUME)
            ACTION_LOUD -> setLevel(1f)
            ACTION_SNOOZE -> snooze()
            ACTION_COMPLETE -> finish(completed = true)
            ACTION_GIVE_UP -> finish(completed = false)
            else -> resume()
        }
        return START_STICKY
    }

    private fun start(intent: Intent) {
        val now = Instant.now()
        val key = intent.getStringExtra(AlarmReceiver.EXTRA_KEY).orEmpty()
        val alarmId = intent.getStringExtra(AlarmReceiver.EXTRA_ALARM_ID).orEmpty()
        val occurrenceId = intent.getStringExtra(AlarmReceiver.EXTRA_OCCURRENCE_ID).orEmpty()
        val fireAt = Instant.ofEpochMilli(intent.getLongExtra(AlarmReceiver.EXTRA_FIRE_AT, now.toEpochMilli()))
        val repo = system.repository
        val existing = repo.activeRings().firstOrNull { it.occurrenceId == occurrenceId }
        val ring = when {
            existing != null -> existing.copy(snoozedUntil = null) // snooze ended or the service was restarted
            else -> {
                val practice = key.startsWith(AlarmScheduler.PRACTICE)
                val schedule = (if (practice) system.scheduler.practiceSchedule(key) else null)
                    ?: repo.alarm(alarmId)
                    ?: AlarmSchedule.newDefault(alarmId)
                val localDate = fireAt.atZone(ZoneId.systemDefault()).toLocalDate()
                val occurrence = Occurrence(occurrenceId, alarmId, localDate, fireAt, schedule.countsForChallenge)
                RingState.start(occurrence, schedule, rangAt = now, practice = practice)
            }
        }
        if (ring.isExpired(now)) {
            PLog.warning(PLog.Category.Alarm) { "Ring for $occurrenceId arrived after its deadline" }
            repo.removeRing(occurrenceId)
            stopRinging()
            return
        }
        repo.putRing(ring)
        _current.value = ring
        goForeground(ring)
        play(ring)
        scheduleDeadline(ring)
        system.scheduler.sync(now) // arm the next occurrence right away
        PLog.info(PLog.Category.Alarm) { "Ringing ${ring.occurrenceId} (practice=${ring.practice})" }
    }

    /** Re-attach to a ring that is still within its deadline (service restarted, app reopened). */
    private fun resume() {
        val now = Instant.now()
        val ring = system.repository.activeRings()
            .filter { !it.isExpired(now) && (it.snoozedUntil == null || !Instant.parse(it.snoozedUntil).isAfter(now)) }
            .maxByOrNull { it.rangAt }
        if (ring == null) {
            stopRinging()
            return
        }
        _current.value = ring
        goForeground(ring)
        play(ring)
        scheduleDeadline(ring)
    }

    private fun snooze() {
        val ring = _current.value ?: return finish(completed = false)
        if (!ring.canSnooze) return
        val snoozed = ring.snoozed(Instant.now())
        system.repository.putRing(snoozed)
        system.scheduler.sync()
        PLog.info(PLog.Category.Alarm) { "Snoozed ${ring.occurrenceId} until ${snoozed.snoozedUntil}, target ${snoozed.target}" }
        stopRinging()
    }

    private fun finish(completed: Boolean) {
        _current.value?.let {
            system.repository.removeRing(it.occurrenceId)
            PLog.info(PLog.Category.Alarm) { "Ring ${it.occurrenceId} ended: ${if (completed) "completed" else "gave up"}" }
        }
        stopRinging()
    }

    private fun goForeground(ring: RingState) {
        val type = when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE && system.scheduler.canScheduleExact() ->
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SYSTEM_EXEMPTED
            else -> ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
        }
        ServiceCompat.startForeground(this, AlarmNotifications.RING_NOTIFICATION_ID, AlarmNotifications.ringNotification(this, ring), type)
        if (wakeLock?.isHeld != true) {
            val ms = (ring.deadline.toEpochMilli() - System.currentTimeMillis()).coerceIn(60_000, AlarmOccurrences.DEADLINE.toMillis())
            wakeLock = getSystemService(PowerManager::class.java)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "pushly:ring")
                .apply { acquire(ms) }
        }
    }

    private fun play(ring: RingState) {
        if (player != null) return
        val resId = soundResource(ring.soundId)
        player = try {
            MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                setDataSource(this@AlarmRingService, Uri.parse("android.resource://$packageName/$resId"))
                isLooping = true
                prepare()
                setVolume(RAMP_START, RAMP_START)
                start()
            }
        } catch (e: Exception) {
            PLog.error(PLog.Category.Alarm) { "Alarm sound failed: ${e.message}" }
            null
        }
        currentVolume = RAMP_START
        targetVolume = 1f
        handler.removeCallbacks(ramp)
        handler.postDelayed(ramp, RAMP_STEP_MS)
        vibrate()
    }

    private val ramp = object : Runnable {
        override fun run() {
            val p = player ?: return
            if (currentVolume < targetVolume) {
                currentVolume = (currentVolume + (1f - RAMP_START) * RAMP_STEP_MS / RAMP_MS).coerceAtMost(targetVolume)
                p.setVolume(currentVolume, currentVolume)
                handler.postDelayed(this, RAMP_STEP_MS)
            }
        }
    }

    private fun setLevel(level: Float) {
        targetVolume = level
        currentVolume = minOf(currentVolume, level)
        player?.setVolume(currentVolume, currentVolume)
        handler.removeCallbacks(ramp)
        handler.postDelayed(ramp, RAMP_STEP_MS)
        if (level < 1f) vibrator?.cancel() else vibrate()
    }

    @Suppress("DEPRECATION")
    private fun vibrate() {
        val v = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(VibratorManager::class.java).defaultVibrator
        } else {
            getSystemService(Vibrator::class.java)
        }
        vibrator = v
        val effect = VibrationEffect.createWaveform(longArrayOf(0, 600, 400, 600, 1400), 0)
        v.vibrate(effect, AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build())
    }

    private fun scheduleDeadline(ring: RingState) {
        handler.removeCallbacks(deadlineReached)
        val delay = ring.deadline.toEpochMilli() - System.currentTimeMillis()
        handler.postDelayed(deadlineReached, delay.coerceAtLeast(0))
    }

    private val deadlineReached = Runnable {
        PLog.info(PLog.Category.Alarm) { "Deadline reached — ring stops" }
        finish(completed = false)
    }

    private fun stopRinging() {
        handler.removeCallbacksAndMessages(null)
        player?.runCatching { stop(); release() }
        player = null
        vibrator?.cancel()
        wakeLock?.takeIf { it.isHeld }?.release()
        wakeLock = null
        _current.value = null
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        player?.runCatching { release() }
        player = null
        vibrator?.cancel()
        wakeLock?.takeIf { it.isHeld }?.release()
        super.onDestroy()
    }

    companion object {
        /** Raw resource of a bundled sound id; unknown ids fall back to the default (doc 04 §8). */
        fun soundResource(id: String): Int = when (AlarmSounds.resourceName(id)) {
            "rise" -> R.raw.rise
            "arena" -> R.raw.arena
            "classic" -> R.raw.classic
            "thunder" -> R.raw.thunder
            "anthem" -> R.raw.anthem
            "drill" -> R.raw.drill
            "sunrise" -> R.raw.sunrise
            else -> R.raw.pulse
        }

        const val ACTION_START = "app.pushly.alarm.START"
        const val ACTION_RESUME = "app.pushly.alarm.RESUME"
        const val ACTION_QUIET = "app.pushly.alarm.QUIET"
        const val ACTION_LOUD = "app.pushly.alarm.LOUD"
        const val ACTION_SNOOZE = "app.pushly.alarm.SNOOZE"
        const val ACTION_COMPLETE = "app.pushly.alarm.COMPLETE"
        const val ACTION_GIVE_UP = "app.pushly.alarm.GIVE_UP"

        private const val QUIET_VOLUME = 0.3f
        private const val RAMP_START = 0.25f
        private const val RAMP_MS = 20_000L
        private const val RAMP_STEP_MS = 500L

        private val _current = MutableStateFlow<RingState?>(null)

        /** The occurrence ringing right now (null when silent). Observed by RingActivity / WakeActivity. */
        val current: StateFlow<RingState?> = _current.asStateFlow()

        fun send(context: Context, action: String) {
            val intent = Intent(context, AlarmRingService::class.java).setAction(action)
            runCatching { context.startService(intent) }
                .onFailure { PLog.error(PLog.Category.Alarm) { "Ring service action $action failed: ${it.message}" } }
        }

        /** Restart ringing if an occurrence is still due (e.g. the process was killed while ringing). */
        fun resumeIfNeeded(context: Context) {
            val now = Instant.now()
            val due = AlarmSystem.get(context).repository.activeRings().any {
                !it.isExpired(now) && (it.snoozedUntil == null || !Instant.parse(it.snoozedUntil).isAfter(now))
            }
            if (due && _current.value == null) {
                runCatching {
                    ContextCompat.startForegroundService(context, Intent(context, AlarmRingService::class.java).setAction(ACTION_RESUME))
                }.onFailure { PLog.warning(PLog.Category.Alarm) { "Could not resume ring: ${it.message}" } }
            }
        }
    }
}
