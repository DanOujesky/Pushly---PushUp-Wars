package app.pushly.feature.stats

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.pushly.core.designsystem.BannerKind
import app.pushly.core.designsystem.GradientProgressBar
import app.pushly.core.designsystem.InlineBanner
import app.pushly.core.designsystem.TokenText
import app.pushly.core.designsystem.achievementGlyph
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.RadiusTokens
import app.pushly.core.designsystem.generated.SpacingTokens
import app.pushly.core.designsystem.generated.TokenColor
import app.pushly.core.designsystem.generated.TypographyTokens
import app.pushly.core.designsystem.heroBrush
import app.pushly.core.designsystem.resolve
import java.time.LocalDate
import java.time.format.TextStyle
import java.util.Locale

/**
 * Profile tab (D-077): your numbers at a glance — level and XP, trophies and league, battle record, push-ups — a 7-day
 * bar strip and achievements progress. Every part opens the full Stats screen on the right section. Same as iOS.
 */
@Composable
fun ProfileStatsCard(vm: StatsViewModel, onOpen: (StatsSection) -> Unit) {
    val s by vm.state.collectAsStateWithLifecycle()
    LaunchedEffect(vm) { vm.start() }
    Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
        s.stats?.let { LevelRow(it.progress) { onOpen(StatsSection.Pushups) } }
        val b = s.battle
        val st = s.stats
        Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
            Tile("🏆", b?.trophies?.toString() ?: "–", b?.let { leagueLabel(it.league, it.tier) } ?: stringResource(R.string.stats_tile_trophies),
                ColorTokens.LeagueGold, Modifier.weight(1f)) { onOpen(StatsSection.Battles) }
            Tile("⚔️", b?.record?.winRate?.let { "$it%" } ?: "–",
                b?.let { stringResource(R.string.stats_tile_wl, it.record.wins, it.record.losses) } ?: stringResource(R.string.stats_win_rate),
                ColorTokens.StateSuccessText, Modifier.weight(1f)) { onOpen(StatsSection.Battles) }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
            Tile("💪", st?.records?.repsAllTime?.toString() ?: "–", stringResource(R.string.stats_tile_all_time),
                ColorTokens.BrandFlameText, Modifier.weight(1f)) { onOpen(StatsSection.Pushups) }
            Tile("⭐", st?.records?.bestSet?.toString() ?: "–", stringResource(R.string.stats_tile_best_set),
                ColorTokens.BrandVoltText, Modifier.weight(1f)) { onOpen(StatsSection.Pushups) }
        }
        when {
            st != null -> {
                Week(st) { onOpen(StatsSection.Pushups) }
                Badges(st.achievements, s.achievements) { onOpen(StatsSection.Badges) }
            }
            s.failed -> InlineBanner(stringResource(R.string.stats_failed), kind = BannerKind.Warning)
            else -> Box(Modifier.fillMaxWidth().heightIn(min = 80.dp), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = ColorTokens.BrandFlame.resolve())
            }
        }
    }
}

private val shape = RoundedCornerShape(RadiusTokens.L)

private fun Modifier.panel(onClick: () -> Unit): Modifier =
    this.clip(shape).clickable(role = Role.Button, onClick = onClick)

@Composable
private fun LevelRow(level: StatsData.Level, onClick: () -> Unit) {
    val volt = ColorTokens.BrandVolt.resolve()
    Row(
        Modifier.fillMaxWidth().panel(onClick).background(ColorTokens.BgSurface.resolve()).padding(SpacingTokens.M)
            .semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(SpacingTokens.M),
    ) {
        Box(Modifier.size(56.dp), contentAlignment = Alignment.Center) {
            Canvas(Modifier.fillMaxSize()) {
                val w = 6.dp.toPx()
                drawArc(Color.White.copy(alpha = 0.08f), 0f, 360f, false, style = Stroke(w))
                drawArc(volt, -90f, 360f * level.fraction.toFloat(), false, style = Stroke(w, cap = StrokeCap.Round))
            }
            TokenText("${level.level}", TypographyTokens.TitleL)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            TokenText(stringResource(R.string.stats_level, level.level), TypographyTokens.TitleM)
            GradientProgressBar(level.fraction.toFloat(), Modifier.fillMaxWidth(), height = 8.dp)
            TokenText(stringResource(R.string.stats_xp_to_next, level.xpForNext - level.xpIntoLevel, level.level + 1),
                TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
        }
    }
}

@Composable
private fun Tile(glyph: String, value: String, label: String, tint: TokenColor, modifier: Modifier, onClick: () -> Unit) {
    val c = tint.resolve()
    Column(
        modifier.panel(onClick)
            .background(Brush.linearGradient(listOf(c.copy(alpha = 0.14f), ColorTokens.BgSurface.resolve())))
            .border(1.dp, ColorTokens.StrokeSubtle.resolve(), shape)
            .padding(SpacingTokens.M)
            .semantics(mergeDescendants = true) {},
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        TokenText(glyph, TypographyTokens.TitleM, modifier = Modifier.clearAndSetSemantics {})
        TokenText(value, TypographyTokens.Stat, color = c, maxLines = 1)
        TokenText(label, TypographyTokens.Caption, color = ColorTokens.TextSecondary.resolve(), maxLines = 1)
    }
}

@Composable
private fun Week(stats: StatsData, onClick: () -> Unit) {
    val days = StatsSeries.lastDays(stats)
    val top = maxOf(days.maxOfOrNull { it.second } ?: 0, 1)
    val total = days.sumOf { it.second }
    val a11y = stringResource(R.string.stats_last7) + ": " + stringResource(R.string.stats_last7_total, total)
    val hero = heroBrush()
    val empty = Color.White.copy(alpha = 0.08f)
    Column(
        Modifier.fillMaxWidth().panel(onClick).background(ColorTokens.BgSurface.resolve()).padding(SpacingTokens.M)
            .clearAndSetSemantics { contentDescription = a11y },
        verticalArrangement = Arrangement.spacedBy(SpacingTokens.S),
    ) {
        Row {
            TokenText(stringResource(R.string.stats_last7), TypographyTokens.TitleS, modifier = Modifier.weight(1f))
            TokenText(stringResource(R.string.stats_last7_total, total), TypographyTokens.BodyS, color = ColorTokens.BrandFlameText.resolve())
        }
        Row(Modifier.fillMaxWidth().height(110.dp), verticalAlignment = Alignment.Bottom,
            horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
            days.forEach { (day, n) ->
                Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    TokenText(if (n > 0) "$n" else "", TypographyTokens.Caption, color = ColorTokens.TextSecondary.resolve(), maxLines = 1)
                    Box(
                        Modifier.fillMaxWidth().height(maxOf(6f, 70f * n / top).dp).clip(RoundedCornerShape(4.dp))
                            .then(if (n > 0) Modifier.background(hero) else Modifier.background(empty)),
                    )
                    val d = runCatching { LocalDate.parse(day) }.getOrNull()
                    TokenText(d?.dayOfWeek?.getDisplayName(TextStyle.NARROW, Locale.getDefault()) ?: "", TypographyTokens.Caption,
                        color = (if (day == stats.to) ColorTokens.TextPrimary else ColorTokens.TextTertiary).resolve())
                }
            }
        }
    }
}

@Composable
private fun Badges(count: StatsData.AchievementCount, items: List<AchievementItem>, onClick: () -> Unit) {
    val recent = items.filter { it.unlocked }.sortedByDescending { it.unlockedAt ?: "" }.take(4)
    Row(
        Modifier.fillMaxWidth().panel(onClick).background(ColorTokens.BgSurface.resolve()).padding(SpacingTokens.M)
            .semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(SpacingTokens.M),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            TokenText(stringResource(R.string.stats_achievements), TypographyTokens.TitleS)
            GradientProgressBar(if (count.total == 0) 0f else count.unlocked.toFloat() / count.total, Modifier.fillMaxWidth(), height = 8.dp)
            TokenText("${count.unlocked} / ${count.total}", TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
        }
        Row(Modifier.clearAndSetSemantics {}, horizontalArrangement = Arrangement.spacedBy((-6).dp)) {
            recent.forEach { a ->
                val tier = tierColor(a.tier).resolve()
                Box(Modifier.size(34.dp).clip(CircleShape).background(ColorTokens.BgElevated.resolve()).border(1.5.dp, tier, CircleShape),
                    contentAlignment = Alignment.Center) {
                    TokenText(achievementGlyph(a.icon), TypographyTokens.Caption, color = tier)
                }
            }
        }
        TokenText("›", TypographyTokens.TitleM, color = ColorTokens.TextTertiary.resolve())
    }
}
