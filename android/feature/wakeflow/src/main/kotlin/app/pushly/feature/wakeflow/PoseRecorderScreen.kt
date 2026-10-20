package app.pushly.feature.wakeflow

import android.content.Intent
import android.os.Build
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import app.pushly.core.designsystem.ArenaBackground
import app.pushly.core.designsystem.GhostButton
import app.pushly.core.designsystem.PrimaryButton
import app.pushly.core.designsystem.PushlyTextField
import app.pushly.core.designsystem.ScreenTitle
import app.pushly.core.designsystem.SecondaryButton
import app.pushly.core.designsystem.SectionLabel
import app.pushly.core.designsystem.TokenText
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.SpacingTokens
import app.pushly.core.designsystem.generated.TouchTarget
import app.pushly.core.designsystem.generated.TypographyTokens
import app.pushly.core.designsystem.resolve
import java.io.File

/**
 * Debug-only pose recorder (P3-04): do a set, label it (human rep count, placement, tags) and share the JSON.
 * Entry point is gated by BuildConfig.DEBUG in :feature:alarm; the FileProvider only exists in debug builds.
 * See docs/qa/pose-recording.md.
 */
@Composable
fun PoseRecorderScreen(onClose: () -> Unit) {
    val model = remember { RepSessionModel(RepSessionModel.Mode.Training, recorder = PoseRecorder()) }
    var labelling by remember { mutableStateOf(false) }
    if (!labelling) {
        RepSessionScreen(model) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                GhostButton(stringResource(R.string.recorder_cancel), onClose)
                Spacer(Modifier.weight(1f))
                PrimaryButton(stringResource(R.string.recorder_stop), onClick = {
                    model.finish()
                    labelling = true
                }, modifier = Modifier.widthIn(max = 180.dp))
            }
        }
    } else {
        LabelForm(model, onClose)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun LabelForm(model: RepSessionModel, onClose: () -> Unit) {
    val context = LocalContext.current
    val recorder = model.recorder ?: return
    var count by remember { mutableIntStateOf(model.state.value.counted) }
    var placement by remember { mutableStateOf("side") }
    var tags by remember { mutableStateOf(setOf<String>()) }
    var notes by remember { mutableStateOf("") }
    var exported by remember { mutableStateOf<File?>(null) }
    ArenaBackground(glow = ColorTokens.BrandFlame) {
        Column(
            Modifier.fillMaxSize().safeDrawingPadding().verticalScroll(rememberScrollState()).padding(SpacingTokens.L),
            verticalArrangement = Arrangement.spacedBy(SpacingTokens.M),
        ) {
            ScreenTitle(stringResource(R.string.recorder_title), token = TypographyTokens.DisplayM)
            TokenText(
                stringResource(R.string.recorder_info, model.state.value.counted, recorder.frameCount),
                TypographyTokens.BodyS,
                color = ColorTokens.TextSecondary.resolve(),
            )
            SectionLabel(stringResource(R.string.recorder_count))
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
                SecondaryButton(stringResource(R.string.recorder_minus), { count = maxOf(count - 1, 0) }, Modifier.widthIn(min = 64.dp))
                TokenText(count.toString(), TypographyTokens.DisplayM)
                SecondaryButton(stringResource(R.string.recorder_plus), { count += 1 }, Modifier.widthIn(min = 64.dp))
            }
            SectionLabel(stringResource(R.string.recorder_placement))
            Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                listOf("side", "front").forEach { p -> Chip(p, placement == p) { placement = p } }
            }
            SectionLabel(stringResource(R.string.recorder_tags))
            FlowRow(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S), verticalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                PoseRecorder.TAGS.forEach { tag ->
                    Chip(tag, tag in tags) { tags = if (tag in tags) tags - tag else tags + tag }
                }
            }
            PushlyTextField(notes, { notes = it }, stringResource(R.string.recorder_notes))
            val file = exported
            if (file == null) {
                PrimaryButton(stringResource(R.string.recorder_save), onClick = {
                    val label = PoseRecorder.Label(count, placement, tags = tags.sorted(), notes = notes)
                    exported = recorder.export(File(context.cacheDir, "pose-recordings"), label, "${Build.MANUFACTURER} ${Build.MODEL}")
                })
            } else {
                PrimaryButton(stringResource(R.string.recorder_share, file.name), onClick = {
                    val uri = FileProvider.getUriForFile(context, "${context.packageName}.poserecorder", file)
                    val send = Intent(Intent.ACTION_SEND).setType("application/json").putExtra(Intent.EXTRA_STREAM, uri)
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    context.startActivity(Intent.createChooser(send, file.name))
                })
            }
            GhostButton(stringResource(R.string.recorder_done), onClose)
        }
    }
}

@Composable
private fun Chip(text: String, selected: Boolean, onClick: () -> Unit) {
    Box(
        Modifier
            .heightIn(min = TouchTarget.Minimum)
            .background(ColorTokens.BgSurface.resolve(), CircleShape)
            .border(1.dp, (if (selected) ColorTokens.BrandFlame else ColorTokens.StrokeSubtle).resolve(), CircleShape)
            .clickable(onClick = onClick)
            .padding(horizontal = SpacingTokens.M),
        contentAlignment = Alignment.Center,
    ) {
        TokenText(text, TypographyTokens.Caption, color = (if (selected) ColorTokens.BrandFlameText else ColorTokens.TextSecondary).resolve())
    }
}
