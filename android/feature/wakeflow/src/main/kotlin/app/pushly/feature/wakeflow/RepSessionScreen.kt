package app.pushly.feature.wakeflow

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import android.speech.tts.TextToSpeech
import android.view.HapticFeedbackConstants
import android.view.WindowManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.view.PreviewView
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.pushly.core.designsystem.ArenaBackground
import app.pushly.core.designsystem.BannerKind
import app.pushly.core.designsystem.GradientProgressBar
import app.pushly.core.designsystem.InlineBanner
import app.pushly.core.designsystem.Pill
import app.pushly.core.designsystem.PrimaryButton
import app.pushly.core.designsystem.ScreenTitle
import app.pushly.core.designsystem.TokenText
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.SpacingTokens
import app.pushly.core.designsystem.generated.TypographyTokens
import app.pushly.core.designsystem.heroBrush
import app.pushly.core.designsystem.resolve
import app.pushly.engine.pose.PoseSession
import app.pushly.engine.rep.Guidance
import app.pushly.engine.rep.PoseLandmark
import app.pushly.engine.rep.RejectReason
import app.pushly.engine.rep.RepState
import java.util.Locale
import kotlin.math.roundToInt

/**
 * Camera push-up screen (doc 05, PS-04/PS-80): live preview, body overlay, counter, hints and guidance. Shows the
 * camera pre-permission explainer first if needed (CLAUDE.md §10). No ads here (§4.5).
 */
@Composable
fun RepSessionScreen(model: RepSessionModel, speakCount: Boolean = false, footer: @Composable ColumnScope.() -> Unit) {
    val context = LocalContext.current
    var granted by remember {
        mutableStateOf(ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED)
    }
    var denied by remember { mutableStateOf(false) }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok ->
        granted = ok
        denied = !ok
    }
    if (!granted) {
        CameraExplainer(denied) {
            if (denied) {
                context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}")))
            } else {
                launcher.launch(Manifest.permission.CAMERA)
            }
        }
        return
    }
    CameraSession(model, speakCount, footer)
}

@Composable
private fun CameraSession(model: RepSessionModel, speakCount: Boolean, footer: @Composable ColumnScope.() -> Unit) {
    val context = LocalContext.current
    val view = LocalView.current
    val owner = LocalLifecycleOwner.current
    val s by model.state.collectAsStateWithLifecycle()
    val previewView = remember {
        PreviewView(context).apply {
            scaleType = PreviewView.ScaleType.FILL_CENTER
            implementationMode = PreviewView.ImplementationMode.COMPATIBLE
        }
    }
    val tts = remember { mutableStateOf<TextToSpeech?>(null) }
    DisposableEffect(speakCount) {
        val engine = if (speakCount) TextToSpeech(context) { } .also { it.language = Locale.ENGLISH } else null
        tts.value = engine
        onDispose { engine?.shutdown() }
    }
    val session = remember {
        PoseSession(context, onFrame = { frame, w, h -> model.ingest(frame, w, h) }, onStatus = model::updateStatus)
    }
    DisposableEffect(owner) {
        model.restartClock()
        session.start(owner, previewView.surfaceProvider)
        val window = (context as? android.app.Activity)?.window
        window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        onDispose {
            session.stop()
            window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }
    LaunchedEffect(s.counted) {
        if (s.counted > 0) {
            view.performHapticFeedback(HapticFeedbackConstants.CONFIRM)
            tts.value?.speak(s.counted.toString(), TextToSpeech.QUEUE_FLUSH, null, "rep")
        }
    }
    LaunchedEffect(s.finished) { if (s.finished) session.stop() }

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        AndroidView({ previewView }, Modifier.fillMaxSize())
        Skeleton(s.landmarks, s.status.imageWidth, s.status.imageHeight, good = s.repState != RepState.NotReady)
        Box(
            Modifier.fillMaxSize().background(
                Brush.verticalGradient(0f to Color.Black.copy(alpha = 0.55f), 0.35f to Color.Transparent, 0.7f to Color.Transparent, 1f to Color.Black.copy(alpha = 0.7f)),
            ),
        )
        Column(
            Modifier.fillMaxSize().safeDrawingPadding().padding(SpacingTokens.L),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(SpacingTokens.M),
        ) {
            val target = model.target
            val shown = if (target != null) maxOf(target - s.counted, 0) else s.counted
            val label = stringResource(if (target != null) R.string.session_pushups_to_go else R.string.session_pushups)
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier.semantics(mergeDescendants = true) { contentDescription = "$shown $label" },
            ) {
                TokenText(shown.toString(), TypographyTokens.DisplayCounter, color = Color.White)
                TokenText(label, TypographyTokens.LabelDisplay, color = Color.White.copy(alpha = 0.85f))
                if (target != null) {
                    GradientProgressBar(s.counted / maxOf(target, 1).toFloat(), Modifier.widthIn(max = 240.dp).padding(top = SpacingTokens.S))
                }
            }
            Spacer(Modifier.weight(1f))
            when {
                s.guidance != Guidance.Ready -> Pill(stringResource(guidanceText(s.guidance)), color = ColorTokens.BrandFlameText)
                s.hint != null -> s.hint?.let { h ->
                    InlineBanner(stringResource(if (h.showTip) tipText(h.reason) else hintText(h.reason)), BannerKind.Warning)
                }
                s.lastQuality != null -> s.lastQuality?.let { q ->
                    Pill(stringResource(R.string.session_form, q), color = if (q >= 70) ColorTokens.StateSuccessText else ColorTokens.StateWarning)
                }
            }
            footer()
        }
        if (BuildConfig.DEBUG) {
            // Performance spike P3-01: frame rate + model on screen in debug builds.
            TokenText(
                "${s.status.fps.roundToInt()} fps · ${s.status.model.asset}",
                TypographyTokens.Caption,
                color = Color.White.copy(alpha = 0.7f),
                modifier = Modifier.safeDrawingPadding().padding(SpacingTokens.S),
            )
        }
    }
}

/** Draws the tracked body over the preview (fill-center, mirrored like the front camera preview). */
@Composable
private fun Skeleton(landmarks: List<PoseLandmark>, imageW: Int, imageH: Int, good: Boolean) {
    val color = (if (good) ColorTokens.StateSuccess else ColorTokens.BrandFlame).resolve()
    Canvas(Modifier.fillMaxSize().clearAndSetSemantics {}) {
        if (landmarks.size != 33 || imageW <= 0 || imageH <= 0) return@Canvas
        val scale = maxOf(size.width / imageW, size.height / imageH)
        val dx = (size.width - imageW * scale) / 2
        val dy = (size.height - imageH * scale) / 2
        fun p(i: Int): Offset? {
            val l = landmarks[i]
            if (l.visibility < 0.5) return null
            return Offset(dx + (1 - l.x).toFloat() * imageW * scale, dy + l.y.toFloat() * imageH * scale)
        }
        for ((a, b) in BONES) {
            val pa = p(a) ?: continue
            val pb = p(b) ?: continue
            drawLine(color.copy(alpha = 0.9f), pa, pb, strokeWidth = 5.dp.toPx(), cap = StrokeCap.Round)
        }
        for (i in JOINTS) p(i)?.let { drawCircle(Color.White, radius = 6.dp.toPx(), center = it) }
    }
}

private val BONES = listOf(
    11 to 12, 11 to 13, 13 to 15, 12 to 14, 14 to 16, 11 to 23, 12 to 24, 23 to 24,
    23 to 25, 25 to 27, 24 to 26, 26 to 28, 27 to 31, 28 to 32,
)
private val JOINTS = listOf(11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28)

/** Camera pre-permission explainer (CLAUDE.md §10, doc 16 privacy). */
@Composable
private fun CameraExplainer(denied: Boolean, onAllow: () -> Unit) {
    ArenaBackground(glow = ColorTokens.BrandVolt) {
        Column(Modifier.fillMaxSize().safeDrawingPadding().padding(SpacingTokens.L), verticalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
            Spacer(Modifier.weight(1f))
            Box(
                Modifier.size(88.dp).clip(RoundedCornerShape(28.dp)).background(heroBrush()).clearAndSetSemantics {},
                contentAlignment = Alignment.Center,
            ) {
                TokenText("●", TypographyTokens.DisplayM, color = Color.White)
            }
            ScreenTitle(stringResource(R.string.camera_title), token = TypographyTokens.DisplayXl)
            TokenText(stringResource(R.string.camera_text), TypographyTokens.Body, color = ColorTokens.TextSecondary.resolve())
            if (denied) InlineBanner(stringResource(R.string.camera_denied), BannerKind.Warning)
            Spacer(Modifier.weight(1f))
            PrimaryButton(stringResource(if (denied) R.string.camera_settings else R.string.camera_allow), onAllow)
        }
    }
}

fun hintText(r: RejectReason): Int = when (r) {
    RejectReason.NotDeepEnough -> R.string.hint_not_deep_enough
    RejectReason.NoLockout -> R.string.hint_no_lockout
    RejectReason.HipsSagging -> R.string.hint_hips_sagging
    RejectReason.HipsPiked -> R.string.hint_hips_piked
    RejectReason.KneesDown -> R.string.hint_knees_down
    RejectReason.BodyNotVisible -> R.string.hint_body_not_visible
    RejectReason.TooFast -> R.string.hint_too_fast
    RejectReason.TooSlow -> R.string.hint_too_slow
    RejectReason.IrregularMotion -> R.string.hint_irregular
    RejectReason.Integrity -> R.string.hint_integrity
}

private fun tipText(r: RejectReason): Int = when (r) {
    RejectReason.NotDeepEnough -> R.string.tip_not_deep_enough
    RejectReason.HipsSagging, RejectReason.HipsPiked -> R.string.tip_hips
    RejectReason.KneesDown -> R.string.tip_knees
    else -> hintText(r)
}

private fun guidanceText(g: Guidance): Int = when (g) {
    Guidance.StepIntoFrame -> R.string.guide_step_into_frame
    Guidance.TurnPhoneToSide -> R.string.guide_turn_phone
    Guidance.ShowWholeBody -> R.string.guide_whole_body
    Guidance.MoveBack -> R.string.guide_move_back
    Guidance.ComeCloser -> R.string.guide_come_closer
    Guidance.TurnOnLight -> R.string.guide_light
    Guidance.GetIntoPlank -> R.string.guide_plank
    Guidance.Ready -> R.string.guide_ready
}
