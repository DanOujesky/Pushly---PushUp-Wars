package app.pushly.feature.alarm

import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind

import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.pushly.core.alarm.ModeType
import app.pushly.core.alarm.RingState
import app.pushly.core.designsystem.ArenaBackground
import app.pushly.core.designsystem.BannerKind
import app.pushly.core.designsystem.GhostButton
import app.pushly.core.designsystem.InlineBanner
import app.pushly.core.designsystem.Pill
import app.pushly.core.designsystem.PrimaryButton
import app.pushly.core.designsystem.PushlyTheme
import app.pushly.core.designsystem.ScreenTitle
import app.pushly.core.designsystem.SecondaryButton
import app.pushly.core.designsystem.SectionLabel
import app.pushly.core.designsystem.TokenText
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.SpacingTokens
import app.pushly.core.designsystem.generated.TypographyTokens
import app.pushly.core.designsystem.resolve
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.Instant
import java.time.ZoneId

internal fun ComponentActivity.arenaWindow() {
    enableEdgeToEdge(
        statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
        navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
    )
    window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    // Back never dismisses a ringing alarm (doc 04 §6.3).
    onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
        override fun handleOnBackPressed() = Unit
    })
}

/** Full-screen ringing screen (doc 04 §6.3): no stop button — "Start push-ups", snooze in escalation, hold to give up. */
class RingActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        arenaWindow()
        setContent {
            PushlyTheme {
                val ring by AlarmRingService.current.collectAsStateWithLifecycle()
                LaunchedEffect(ring == null) {
                    if (ring == null) {
                        delay(1_500) // the service may still be starting
                        if (AlarmRingService.current.value == null) finish()
                    }
                }
                ring?.let { r ->
                    RingScreen(
                        ring = r,
                        onStart = {
                            startActivity(android.content.Intent(this, WakeActivity::class.java))
                        },
                        onSnooze = {
                            AlarmRingService.send(this, AlarmRingService.ACTION_SNOOZE)
                            finish()
                        },
                        onGiveUp = {
                            AlarmRingService.send(this, AlarmRingService.ACTION_GIVE_UP)
                            finish()
                        },
                    )
                }
            }
        }
    }
}

@Composable
fun RingScreen(ring: RingState, onStart: () -> Unit, onSnooze: () -> Unit, onGiveUp: () -> Unit) {
    val context = LocalContext.current
    val zone = ZoneId.systemDefault()
    val t0 = ring.t0Instant.atZone(zone).toLocalTime()
    ArenaBackground(glow = ColorTokens.BrandFlame, glowAlignment = Alignment.Center, glowOffset = DpOffset(0.dp, (-120).dp)) {
        Column(
            Modifier.fillMaxSize().safeDrawingPadding().padding(SpacingTokens.L),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Column(
                Modifier.weight(1f).verticalScroll(rememberScrollState()),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(SpacingTokens.M, Alignment.CenterVertically),
            ) {
                Pill(
                    stringResource(if (ring.practice) R.string.ring_practice else R.string.ring_alarm_ringing),
                    color = ColorTokens.BrandFlameText,
                )
                val time = TimeFormat.parts(context, t0)
                TokenText(time.main, TypographyTokens.DisplayTime, textAlign = TextAlign.Center)
                time.suffix?.let { TokenText(it, TypographyTokens.LabelDisplay, color = ColorTokens.TextTertiary.resolve()) }
                ScreenTitle(
                    ring.label.ifBlank { stringResource(R.string.ring_default_title) },
                    token = TypographyTokens.DisplayM,
                    textAlign = TextAlign.Center,
                )
                Box(
                    Modifier
                        .clip(RoundedCornerShape(24.dp))
                        .background(ColorTokens.BgSurface.resolve())
                        .border(1.dp, ColorTokens.StrokeSubtle.resolve(), RoundedCornerShape(24.dp))
                        .padding(horizontal = SpacingTokens.L, vertical = SpacingTokens.M),
                    contentAlignment = Alignment.Center,
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        TokenText(ring.target.toString(), TypographyTokens.Stat)
                        TokenText(stringResource(R.string.ring_pushups_to_go), TypographyTokens.LabelDisplay, color = ColorTokens.TextTertiary.resolve())
                        TokenText(ModeText.summary(context, ring.mode), TypographyTokens.BodyS, color = ColorTokens.TextSecondary.resolve(), textAlign = TextAlign.Center)
                    }
                }
                ring.beatTheClockEndsAt?.let { ends -> BeatTheClockBanner(ends) }
                if (ring.snoozesUsed > 0) {
                    TokenText(
                        stringResource(R.string.ring_snoozes_used, ring.snoozesUsed, ring.mode.maxSnoozes ?: 0),
                        TypographyTokens.Caption,
                        color = ColorTokens.TextTertiary.resolve(),
                    )
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.Sm), horizontalAlignment = Alignment.CenterHorizontally) {
                PrimaryButton(stringResource(R.string.ring_start_pushups), onStart)
                if (ring.canSnooze) {
                    SecondaryButton(stringResource(R.string.ring_snooze, ring.mode.snoozeMinutes ?: 5, ring.mode.snoozeAddsReps ?: 0), onSnooze)
                }
                HoldToGiveUp(onGiveUp)
            }
        }
    }
}

@Composable
internal fun BeatTheClockBanner(endsAt: Instant) {
    var left by remember { mutableStateOf(Duration.between(Instant.now(), endsAt)) }
    LaunchedEffect(endsAt) {
        while (true) {
            left = Duration.between(Instant.now(), endsAt)
            if (left.isNegative) break
            delay(250)
        }
    }
    val secs = left.seconds.coerceAtLeast(0)
    InlineBanner(
        if (secs > 0) stringResource(R.string.ring_beat_clock_left, secs / 60, secs % 60) else stringResource(R.string.ring_beat_clock_over),
        if (secs > 0) BannerKind.Warning else BannerKind.Error,
    )
}

/** "Give up" needs a 3-second hold (doc 04 §6.3) so it can't happen by accident while half asleep. */
@Composable
internal fun HoldToGiveUp(onGiveUp: () -> Unit) {
    val progress = remember { Animatable(0f) }
    val scope = rememberCoroutineScope()
    var job by remember { mutableStateOf<Job?>(null) }
    val label = stringResource(R.string.ring_give_up_hold)
    val danger = ColorTokens.StateDanger.resolve()
    Box(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .clip(CircleShape)
            .drawBehind { drawRect(danger.copy(alpha = 0.18f), size = size.copy(width = size.width * progress.value)) }
            .semantics {
                role = Role.Button
                onClick(label) { onGiveUp(); true }
            }
            .pointerInput(Unit) {
                awaitEachGesture {
                    awaitFirstDown()
                    job = scope.launch {
                        progress.snapTo(0f)
                        progress.animateTo(1f, tween(3_000, easing = LinearEasing))
                        onGiveUp()
                    }
                    waitForUpOrCancellation()
                    job?.cancel()
                    scope.launch { progress.animateTo(0f, tween(200)) }
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        TokenText(label, TypographyTokens.BodyS, color = ColorTokens.TextTertiary.resolve())
    }
}
