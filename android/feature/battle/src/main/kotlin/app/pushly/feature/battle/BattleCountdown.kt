package app.pushly.feature.battle

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.material3.Text
import app.pushly.core.designsystem.Avatar
import app.pushly.core.designsystem.TokenText
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.RadiusTokens
import app.pushly.core.designsystem.generated.SpacingTokens
import app.pushly.core.designsystem.generated.TypographyTokens
import app.pushly.core.designsystem.resolve
import app.pushly.core.designsystem.toTextStyle

/**
 * Before a battle (D-081): the server starts it 8 s after both phones are ready. The first seconds say GET READY
 * (who you fight, get into position, side view), then a big 5-4-3-2-1 with a ring, a beep and a buzz each second,
 * then GO. Same as iOS `BattleCountdown`.
 */
object BattleCountdown {
    /** The last seconds that are counted out loud and big. */
    const val COUNTED = 5

    sealed interface Stage {
        data object GetReady : Stage
        data class Count(val n: Int) : Stage
    }

    fun stage(secondsLeft: Int): Stage = if (secondsLeft > COUNTED) Stage.GetReady else Stage.Count(maxOf(1, secondsLeft))
}

@Composable
internal fun BattleCountdownOverlay(secondsLeft: Int, opponent: String, opponentAvatar: String?, mode: String) {
    val haptics = LocalHapticFeedback.current
    LaunchedEffect(secondsLeft) { haptics.performHapticFeedback(HapticFeedbackType.LongPress) }
    val stage = BattleCountdown.stage(secondsLeft)
    val a11y = when (stage) {
        BattleCountdown.Stage.GetReady -> stringResource(R.string.battle_cd_get_ready_a11y, opponent, secondsLeft)
        is BattleCountdown.Stage.Count -> stringResource(R.string.battle_cd_starts_in, stage.n)
    }
    Box(
        Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.55f)).clearAndSetSemantics { contentDescription = a11y },
        contentAlignment = Alignment.Center,
    ) {
        when (stage) {
            BattleCountdown.Stage.GetReady -> GetReady(secondsLeft, opponent, opponentAvatar, mode)
            is BattleCountdown.Stage.Count -> Count(stage.n)
        }
    }
}

@Composable
private fun GetReady(secondsLeft: Int, opponent: String, avatar: String?, mode: String) {
    val hero = Brush.linearGradient(listOf(ColorTokens.BrandFlame.resolve(), ColorTokens.BrandVolt.resolve()))
    Column(Modifier.padding(SpacingTokens.L), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(SpacingTokens.L)) {
        Text(stringResource(R.string.battle_cd_get_ready), style = TypographyTokens.DisplayL.toTextStyle().copy(brush = hero))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.L)) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
                Box(Modifier.size(72.dp).clip(CircleShape).background(ColorTokens.BrandFlame.resolve().copy(alpha = 0.18f)), contentAlignment = Alignment.Center) {
                    TokenText("💪", TypographyTokens.DisplayM)
                }
                TokenText(stringResource(R.string.battle_cd_you), TypographyTokens.TitleS, color = Color.White)
            }
            TokenText("VS", TypographyTokens.DisplayM, color = Color.White.copy(alpha = 0.8f))
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
                Avatar(opponent, avatar, size = 72.dp)
                TokenText(opponent, TypographyTokens.TitleS, color = Color.White, maxLines = 1)
            }
        }
        TokenText(modeTitle(mode), TypographyTokens.LabelDisplay, color = Color.White.copy(alpha = 0.8f))
        Column(
            Modifier.clip(RoundedCornerShape(RadiusTokens.M)).background(Color.Black.copy(alpha = 0.45f)).padding(SpacingTokens.M),
            verticalArrangement = Arrangement.spacedBy(SpacingTokens.Xs),
        ) {
            TokenText("⬇ " + stringResource(R.string.battle_cd_plank), TypographyTokens.BodyS, color = Color.White)
            TokenText("📷 " + stringResource(R.string.battle_cd_side), TypographyTokens.BodyS, color = Color.White)
        }
        TokenText(stringResource(R.string.battle_cd_in, secondsLeft), TypographyTokens.Caption, color = Color.White.copy(alpha = 0.7f))
    }
}

@Composable
private fun Count(n: Int) {
    val flame = ColorTokens.BrandFlame.resolve()
    val volt = ColorTokens.BrandVolt.resolve()
    val sweep by animateFloatAsState(n.toFloat() / BattleCountdown.COUNTED, tween(900), label = "ring")
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
        Box(Modifier.size(230.dp), contentAlignment = Alignment.Center) {
            Canvas(Modifier.size(230.dp)) {
                val stroke = Stroke(width = 12.dp.toPx(), cap = StrokeCap.Round)
                drawArc(Color.White.copy(alpha = 0.15f), 0f, 360f, false, style = stroke)
                drawArc(Brush.linearGradient(listOf(flame, volt)), -90f, 360f * sweep, false, style = stroke)
            }
            AnimatedContent(
                targetState = n,
                transitionSpec = { (scaleIn(initialScale = 1.8f) + fadeIn()) togetherWith fadeOut(tween(150)) },
                label = "count",
            ) { value ->
                Text("$value", style = TextStyle(fontSize = 140.sp, fontWeight = FontWeight.Black, color = Color.White, textAlign = TextAlign.Center))
            }
        }
        TokenText(stringResource(if (n <= 2) R.string.battle_cd_arms else R.string.battle_get_ready), TypographyTokens.TitleM,
            color = Color.White.copy(alpha = 0.9f))
    }
}
