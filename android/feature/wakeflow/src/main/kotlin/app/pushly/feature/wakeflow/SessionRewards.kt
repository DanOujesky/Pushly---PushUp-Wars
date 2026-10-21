package app.pushly.feature.wakeflow

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import app.pushly.core.designsystem.BannerKind
import app.pushly.core.designsystem.GradientProgressBar
import app.pushly.core.designsystem.InlineBanner
import app.pushly.core.designsystem.Pill
import app.pushly.core.designsystem.TokenText
import app.pushly.core.designsystem.achievementGlyph
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.MotionTokens
import app.pushly.core.designsystem.generated.RadiusTokens
import app.pushly.core.designsystem.generated.SpacingTokens
import app.pushly.core.designsystem.generated.TypographyTokens
import app.pushly.core.designsystem.resolve

/**
 * What a validated session earned (doc 10 §3–5): XP, level progress, a new best set and unlocked achievements. Shown on
 * the wake and training result screens once the server answered. Same as iOS `SessionRewardsView`. No ads here.
 */
@Composable
fun SessionRewards(result: SessionResult) {
    val progress = result.progress ?: return
    var appeared by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { appeared = true }
    val bar by animateFloatAsState(
        if (appeared) progress.xpIntoLevel.toFloat() / maxOf(progress.xpForNext, 1) else 0f,
        tween(MotionTokens.SLOW_MS),
        label = "xp",
    )
    Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.Sm)) {
        if (result.newBestSet == true) InlineBanner(stringResource(R.string.rewards_new_best_set), BannerKind.Success)
        Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
            if (progress.xpGained > 0) Pill(stringResource(R.string.rewards_xp, progress.xpGained), color = ColorTokens.BrandVoltText)
            Pill(
                stringResource(if (progress.levelUp) R.string.rewards_level_up else R.string.rewards_level, progress.level),
                color = if (progress.levelUp) ColorTokens.LeagueGold else null,
            )
        }
        GradientProgressBar(bar)
        progress.newAchievements.forEach { UnlockedRow(it) }
    }
}

@Composable
private fun UnlockedRow(a: SessionResult.Progress.Unlocked) {
    val gold = ColorTokens.LeagueGold.resolve()
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(RadiusTokens.M))
            .background(ColorTokens.BgSurface.resolve())
            .padding(SpacingTokens.Sm)
            .semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(SpacingTokens.M),
    ) {
        Box(Modifier.size(44.dp).clip(CircleShape).background(gold.copy(alpha = 0.15f)), contentAlignment = Alignment.Center) {
            TokenText(achievementGlyph(a.icon), TypographyTokens.TitleS, color = gold)
        }
        Column(Modifier.weight(1f)) {
            TokenText(stringResource(R.string.rewards_unlocked), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
            TokenText(a.title, TypographyTokens.TitleS)
            TokenText(a.description, TypographyTokens.Caption, color = ColorTokens.TextSecondary.resolve())
        }
        if (a.xp > 0) TokenText(stringResource(R.string.rewards_xp, a.xp), TypographyTokens.BodyS, color = ColorTokens.BrandVoltText.resolve())
    }
}
