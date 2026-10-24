package app.pushly.feature.wakeflow

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool
import android.speech.tts.TextToSpeech
import java.util.Locale

/**
 * Sound feedback during a rep session (same as iOS RepSounds): a "pop" per counted rep, a soft thud for a rep that
 * didn't count, a chime when the target is reached, and the spoken count. Settings in prefs "pushly.sounds":
 * `enabled` (master, default on) and `voice` (count aloud, default on).
 */
class RepSounds(context: Context) {
    /** Opponent / Lead / Behind / Go: battles (D-066). */
    enum class Effect { Count, Miss, Done, Opponent, Lead, Behind, Go }

    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val pool = SoundPool.Builder()
        .setMaxStreams(4)
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build(),
        )
        .build()
    private val ids = mapOf(
        Effect.Count to pool.load(context, R.raw.rep_count, 1),
        Effect.Miss to pool.load(context, R.raw.rep_miss, 1),
        Effect.Done to pool.load(context, R.raw.rep_done, 1),
        Effect.Opponent to pool.load(context, R.raw.rep_opp, 1),
        Effect.Lead to pool.load(context, R.raw.battle_lead, 1),
        Effect.Behind to pool.load(context, R.raw.battle_behind, 1),
        Effect.Go to pool.load(context, R.raw.battle_go, 1),
    )
    private var ttsReady = false
    private val tts: TextToSpeech = TextToSpeech(context.applicationContext) { status ->
        if (status == TextToSpeech.SUCCESS) {
            ttsReady = true
            tts.language = Locale.ENGLISH
        }
    }

    var enabled: Boolean
        get() = prefs.getBoolean(KEY_ENABLED, true)
        set(value) = prefs.edit().putBoolean(KEY_ENABLED, value).apply()

    var voice: Boolean
        get() = prefs.getBoolean(KEY_VOICE, true)
        set(value) = prefs.edit().putBoolean(KEY_VOICE, value).apply()

    fun play(effect: Effect) {
        if (!enabled) return
        ids[effect]?.let { pool.play(it, 1f, 1f, 1, 0, 1f) }
    }

    /** Spoken line (rep count, announcer): only the master switch applies; interrupts whatever is being said. */
    fun announce(text: String) {
        if (!enabled || !ttsReady) return
        tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, "rep")
    }

    fun release() {
        tts.shutdown()
        pool.release()
    }

    companion object {
        const val PREFS = "pushly.sounds"
        const val KEY_ENABLED = "enabled"
        const val KEY_VOICE = "voice"
    }
}
