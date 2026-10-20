package app.pushly.feature.alarm

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.pushly.core.designsystem.ArenaBackground
import app.pushly.core.designsystem.BannerKind
import app.pushly.core.designsystem.GhostButton
import app.pushly.core.designsystem.InlineBanner
import app.pushly.core.designsystem.Pill
import app.pushly.core.designsystem.PrimaryButton
import app.pushly.core.designsystem.PushlyTheme
import app.pushly.core.designsystem.SectionLabel
import app.pushly.core.designsystem.TokenText
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.SpacingTokens
import app.pushly.core.designsystem.generated.TypographyTokens
import app.pushly.core.designsystem.resolve
import app.pushly.feature.wakeflow.RepSessionModel
import app.pushly.feature.wakeflow.RepSessionScreen
import app.pushly.feature.wakeflow.SessionResult
import app.pushly.feature.wakeflow.SessionServices
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow

/**
 * Wake session (doc 04 §3, PS-30…PS-34): the camera counts the push-ups under the mode rules ([WakeChallenge]); when
 * it is over the result screen shows the provisional result, then the server's. The alarm keeps ringing quietly
 * (30 %) while the camera is open; sets mode rings loudly again when a rest is over. Debug builds keep a "Complete"
 * button for testing without a camera; it is compiled out of release behaviour (CLAUDE.md §10).
 */
class WakeActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        arenaWindow()
        val ring = AlarmRingService.current.value
        if (ring == null) {
            finish()
            return
        }
        AlarmRingService.send(this, AlarmRingService.ACTION_QUIET)
        val services = SessionServices.shared
        var over by mutableStateOf(false)
        val challenge = WakeChallenge(
            ring,
            services,
            onOver = { succeeded ->
                // Stops the alarm either way: beaten, given up, or the mode's window / rest ran out.
                AlarmRingService.send(this, if (succeeded) AlarmRingService.ACTION_COMPLETE else AlarmRingService.ACTION_GIVE_UP)
                over = true
            },
            onRestOver = { AlarmRingService.send(this, AlarmRingService.ACTION_LOUD) },
            onSetStarted = { AlarmRingService.send(this, AlarmRingService.ACTION_QUIET) },
        )
        setContent {
            PushlyTheme {
                LaunchedEffect(Unit) { challenge.anchor = services?.anchor() }
                LaunchedEffect(over) {
                    while (!over) {
                        challenge.tick()
                        delay(250)
                    }
                }
                if (over) {
                    WakeResult(challenge, services) { finish() }
                } else {
                    WakeCamera(challenge, onBack = {
                        AlarmRingService.send(this@WakeActivity, AlarmRingService.ACTION_LOUD)
                        finish()
                    }, onDebugComplete = {
                        AlarmRingService.send(this@WakeActivity, AlarmRingService.ACTION_COMPLETE)
                        finish()
                    })
                }
            }
        }
    }
}

@Composable
private fun WakeCamera(challenge: WakeChallenge, onBack: () -> Unit, onDebugComplete: () -> Unit) {
    val display by challenge.display.collectAsStateWithLifecycle()
    val counter = display?.let { counterText(it) }
    LaunchedEffect(counter) { challenge.reps.setDisplay(counter) }
    val ends = challenge.ring.beatTheClockEndsAt
    RepSessionScreen(challenge.reps) {
        Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
            if (ends != null) BeatTheClockBanner(ends)
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                if (BuildConfig.DEBUG) GhostButton(stringResource(R.string.wake_debug_complete), onClick = onDebugComplete)
                Spacer(Modifier.weight(1f))
                GhostButton(stringResource(R.string.wake_back_to_alarm), onClick = onBack)
            }
            HoldToGiveUp { challenge.giveUp() }
        }
    }
}

@Composable
private fun counterText(d: WakeChallenge.Display): RepSessionModel.CounterDisplay = when (d.kind) {
    WakeChallenge.Display.Kind.SprintReady ->
        RepSessionModel.CounterDisplay(stringResource(R.string.wake_seconds, d.value), stringResource(R.string.wake_sprint_ready))
    WakeChallenge.Display.Kind.Countdown ->
        RepSessionModel.CounterDisplay(d.value.toString(), stringResource(R.string.wake_get_ready))
    WakeChallenge.Display.Kind.Sprinting -> RepSessionModel.CounterDisplay(
        d.value.toString(),
        stringResource(R.string.wake_sprint_left, d.a, d.b),
        d.value / maxOf(d.b, 1).toFloat(),
    )
    WakeChallenge.Display.Kind.Rest ->
        RepSessionModel.CounterDisplay(stringResource(R.string.wake_seconds, d.value), stringResource(R.string.wake_rest_next, d.a, d.b))
    WakeChallenge.Display.Kind.StartSetNow ->
        RepSessionModel.CounterDisplay(stringResource(R.string.wake_seconds, d.value), stringResource(R.string.wake_start_set_now, d.a))
    WakeChallenge.Display.Kind.Set -> RepSessionModel.CounterDisplay(
        stringResource(R.string.wake_set_progress, d.value, d.a),
        stringResource(R.string.wake_set_of, d.b),
        d.value / maxOf(d.a, 1).toFloat(),
    )
}

/** Completion (PS-32) / failure (PS-33): provisional result first, then the server's (PS-90). No ads (§4.5). */
@Composable
private fun WakeResult(challenge: WakeChallenge, services: SessionServices?, onDone: () -> Unit) {
    val decision by challenge.decision.collectAsStateWithLifecycle()
    val noResults = remember { MutableStateFlow<Map<String, SessionResult>>(emptyMap()) }
    val noPending = remember { MutableStateFlow<Set<String>>(emptySet()) }
    val results by (services?.uploader?.results ?: noResults).collectAsStateWithLifecycle()
    val pending by (services?.uploader?.pending ?: noPending).collectAsStateWithLifecycle()
    val result = results[challenge.sessionId]
    val serverStatus = result?.wake?.status?.takeIf { it != "not_challenge" }
    val succeeded = (serverStatus ?: decision?.status) == "succeeded"
    val summary = remember { challenge.reps.summary() }
    val context = LocalContext.current
    ArenaBackground(glow = if (succeeded) ColorTokens.StateSuccess else ColorTokens.BrandFlame) {
        Column(
            Modifier.fillMaxSize().safeDrawingPadding().padding(SpacingTokens.L),
            verticalArrangement = Arrangement.spacedBy(SpacingTokens.M),
        ) {
            Spacer(Modifier.weight(1f))
            SectionLabel(
                stringResource(if (succeeded) R.string.wake_result_beaten else R.string.wake_result_lost),
                color = if (succeeded) ColorTokens.StateSuccessText else ColorTokens.TextSecondary,
            )
            TokenText(summary.reps.toString(), TypographyTokens.DisplayCounter)
            TokenText(stringResource(R.string.wake_result_pushups), TypographyTokens.LabelDisplay, color = ColorTokens.TextTertiary.resolve())
            Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                Pill(stringResource(R.string.wake_result_form, summary.averageQuality), color = ColorTokens.StateSuccessText)
                Pill(stringResource(R.string.wake_result_duration, summary.durationSeconds / 60, summary.durationSeconds % 60))
            }
            if (succeeded) {
                if (result != null) {
                    Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                        val points = result.wake?.points ?: 0
                        if (points > 0) Pill(stringResource(R.string.wake_result_points, points), color = ColorTokens.BrandFlameText)
                        Pill(stringResource(R.string.wake_result_streak, result.streak.current))
                    }
                    if (!result.verified) InlineBanner(stringResource(R.string.wake_result_unverified), BannerKind.Warning)
                } else {
                    val waiting = pending.any { it.endsWith(challenge.sessionId) }
                    TokenText(
                        stringResource(if (waiting) R.string.wake_result_verifying else R.string.wake_result_offline),
                        TypographyTokens.BodyS,
                        color = ColorTokens.TextTertiary.resolve(),
                    )
                }
            } else {
                val reason = result?.wake?.reason ?: decision?.reason
                TokenText(
                    context.getString(
                        when (reason) {
                            "window_expired" -> R.string.wake_fail_window
                            "sprint_too_few" -> R.string.wake_fail_sprint
                            "rest_too_long" -> R.string.wake_fail_rest
                            else -> R.string.wake_fail_default
                        },
                    ),
                    TypographyTokens.Body,
                    color = ColorTokens.TextSecondary.resolve(),
                )
                val streak = result?.streak
                if (serverStatus == "failed" && streak != null && streak.current > 0) {
                    InlineBanner(stringResource(R.string.wake_fail_freeze, streak.current), BannerKind.Info)
                }
                TokenText(stringResource(R.string.wake_fail_train), TypographyTokens.BodyS, color = ColorTokens.TextTertiary.resolve())
            }
            Spacer(Modifier.weight(1f))
            PrimaryButton(stringResource(R.string.wake_result_done), onDone)
        }
    }
}
