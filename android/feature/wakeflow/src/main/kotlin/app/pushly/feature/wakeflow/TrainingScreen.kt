package app.pushly.feature.wakeflow

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
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
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.pushly.core.designsystem.ArenaBackground
import app.pushly.core.designsystem.BannerKind
import app.pushly.core.designsystem.GhostButton
import app.pushly.core.designsystem.InlineBanner
import app.pushly.core.designsystem.Pill
import app.pushly.core.designsystem.PrimaryButton
import app.pushly.core.designsystem.SectionLabel
import app.pushly.core.designsystem.TokenText
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.SpacingTokens
import app.pushly.core.designsystem.generated.TypographyTokens
import app.pushly.core.designsystem.resolve
import kotlinx.coroutines.flow.MutableStateFlow

/** Free training (PS-80): camera counts push-ups, no target; uploaded as a training session (totals, not the streak). */
@Composable
fun TrainingScreen(onClose: () -> Unit) {
    val context = LocalContext.current
    val prefs = remember { context.getSharedPreferences(RepSounds.PREFS, Context.MODE_PRIVATE) }
    var speak by remember { mutableStateOf(prefs.getBoolean(RepSounds.KEY_VOICE, true)) }
    var summary by remember { mutableStateOf<RepSessionModel.Summary?>(null) }
    val model = remember { RepSessionModel(RepSessionModel.Mode.Training) }
    val services = SessionServices.shared
    var anchor by remember { mutableStateOf<ServerAnchor?>(null) }
    var sessionId by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) { anchor = services?.anchor() }
    val done = summary
    if (done != null) {
        TrainingSummary(done, services, sessionId, onClose)
        return
    }
    RepSessionScreen(model, speakCount = speak) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            GhostButton(stringResource(if (speak) R.string.training_voice_on else R.string.training_voice_off), onClick = {
                speak = !speak
                prefs.edit().putBoolean(RepSounds.KEY_VOICE, speak).apply()
            })
            Spacer(Modifier.weight(1f))
            PrimaryButton(stringResource(R.string.training_end), onClick = {
                model.finish()
                summary = model.summary()
                if (model.state.value.counted > 0) sessionId = services?.submitTraining(model, anchor)
            }, modifier = Modifier.widthIn(max = 160.dp))
        }
    }
}

@Composable
internal fun TrainingSummary(
    summary: RepSessionModel.Summary,
    services: SessionServices?,
    sessionId: String?,
    onDone: () -> Unit,
    workout: Workout? = null,
    sets: List<WorkoutRunner.SetResult> = emptyList(),
) {
    val noResults = remember { MutableStateFlow<Map<String, SessionResult>>(emptyMap()) }
    val results by (services?.uploader?.results ?: noResults).collectAsStateWithLifecycle()
    val result = sessionId?.let { results[it] }
    ArenaBackground(glow = ColorTokens.BrandFlame) {
        Column(Modifier.fillMaxSize().safeDrawingPadding().padding(SpacingTokens.L), verticalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
            Column(
                Modifier.weight(1f).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(SpacingTokens.M),
            ) {
                Spacer(Modifier.height(SpacingTokens.Xxl))
                if (workout != null) {
                    SectionLabel(stringResource(R.string.workout_done), color = ColorTokens.BrandFlameText)
                    TokenText(workout.name, TypographyTokens.TitleM)
                } else {
                    SectionLabel(stringResource(R.string.training_done), color = ColorTokens.BrandFlameText)
                }
                TokenText(summary.reps.toString(), TypographyTokens.DisplayCounter)
                TokenText(stringResource(R.string.session_pushups), TypographyTokens.LabelDisplay, color = ColorTokens.TextTertiary.resolve())
                Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                    Pill(stringResource(R.string.session_form, summary.averageQuality), color = ColorTokens.StateSuccessText)
                    Pill(stringResource(R.string.training_duration, summary.durationSeconds / 60, summary.durationSeconds % 60))
                }
                if (workout != null && sets.isNotEmpty()) WorkoutSetResults(workout, sets)
                val total = summary.rejected.values.sum()
                summary.rejected.maxByOrNull { it.value }?.key?.let { top ->
                    if (total > 0) InlineBanner(stringResource(R.string.training_rejected, total, stringResource(hintText(top))), BannerKind.Info)
                }
                if (result != null) {
                    SessionRewards(result)
                } else if (sessionId != null) {
                    TokenText(stringResource(R.string.rewards_pending), TypographyTokens.BodyS, color = ColorTokens.TextTertiary.resolve())
                }
            }
            PrimaryButton(stringResource(R.string.training_close), onDone)
        }
    }
}
