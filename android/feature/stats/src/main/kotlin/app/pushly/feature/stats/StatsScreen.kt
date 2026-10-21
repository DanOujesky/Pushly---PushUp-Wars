package app.pushly.feature.stats

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.pushly.core.designsystem.ArenaBackground
import app.pushly.core.designsystem.BannerKind
import app.pushly.core.designsystem.GradientProgressBar
import app.pushly.core.designsystem.InlineBanner
import app.pushly.core.designsystem.MinTouchTarget
import app.pushly.core.designsystem.PushlyCard
import app.pushly.core.designsystem.ScreenTitle
import app.pushly.core.designsystem.SectionLabel
import app.pushly.core.designsystem.TokenText
import app.pushly.core.designsystem.achievementGlyph
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.RadiusTokens
import app.pushly.core.designsystem.generated.SpacingTokens
import app.pushly.core.designsystem.generated.TypographyTokens
import app.pushly.core.designsystem.resolve
import kotlin.math.abs

/** Profile → Stats (doc 10 §2): level, period picker, KPI tiles with Δ, charts 1–4 and 6, records, achievements. */
@Composable
fun StatsScreen(vm: StatsViewModel, onBack: () -> Unit, onAchievements: () -> Unit, modifier: Modifier = Modifier) {
    val s by vm.state.collectAsStateWithLifecycle()
    LaunchedEffect(vm) { vm.start() }

    ArenaBackground(modifier, glow = ColorTokens.BrandCyan, glowOffset = DpOffset(0.dp, (-260).dp)) {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(SpacingTokens.L),
            verticalArrangement = Arrangement.spacedBy(SpacingTokens.L),
        ) {
            TextButton(onClick = onBack, modifier = Modifier.heightIn(min = MinTouchTarget)) {
                Text(stringResource(R.string.stats_back), color = ColorTokens.BrandFlameText.resolve())
            }
            ScreenTitle(stringResource(R.string.stats_title), token = TypographyTokens.DisplayM)
            PeriodPicker(s.period, vm::selectPeriod)
            val stats = s.stats
            when {
                stats != null -> StatsContent(stats, onAchievements)
                s.failed -> {
                    InlineBanner(stringResource(R.string.stats_failed), kind = BannerKind.Warning)
                    TextButton(onClick = vm::reload) { Text(stringResource(R.string.stats_retry)) }
                }
                else -> Box(Modifier.fillMaxWidth().heightIn(min = 200.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = ColorTokens.BrandFlame.resolve())
                }
            }
        }
    }
}

@Composable
private fun PeriodPicker(selected: StatsData.Period, onSelect: (StatsData.Period) -> Unit) {
    val labels = mapOf(
        StatsData.Period.Week to R.string.stats_week,
        StatsData.Period.Month to R.string.stats_month,
        StatsData.Period.Year to R.string.stats_year,
        StatsData.Period.All to R.string.stats_all,
    )
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(RadiusTokens.M)).background(ColorTokens.BgSurface.resolve()).padding(4.dp),
    ) {
        StatsData.Period.entries.forEach { p ->
            val on = p == selected
            Box(
                Modifier
                    .weight(1f)
                    .heightIn(min = MinTouchTarget)
                    .clip(RoundedCornerShape(RadiusTokens.S))
                    .background(if (on) ColorTokens.BgElevated.resolve() else ColorTokens.BgSurface.resolve())
                    .selectable(on, role = Role.Tab) { onSelect(p) },
                contentAlignment = Alignment.Center,
            ) {
                TokenText(
                    stringResource(labels.getValue(p)),
                    TypographyTokens.BodyS,
                    color = if (on) ColorTokens.TextPrimary.resolve() else ColorTokens.TextTertiary.resolve(),
                )
            }
        }
    }
}

@Composable
private fun StatsContent(stats: StatsData, onAchievements: () -> Unit) {
    LevelCard(stats.progress)
    val k = stats.kpis
    Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
        StatTile(stringResource(R.string.stats_kpi_reps), "${k.reps}", StatsSeries.delta(k.reps, k.repsPrev), "", Modifier.weight(1f))
        StatTile(stringResource(R.string.stats_kpi_best_set), "${k.bestSet}", StatsSeries.delta(k.bestSet, k.bestSetPrev), "", Modifier.weight(1f))
    }
    Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
        StatTile(
            stringResource(R.string.stats_kpi_wake),
            k.wakeSuccessPct?.let { "$it %" } ?: "–",
            StatsSeries.delta(k.wakeSuccessPct, k.wakeSuccessPctPrev),
            " %",
            Modifier.weight(1f),
        )
        StatTile(stringResource(R.string.stats_kpi_form), k.avgQuality?.toString() ?: "–",
            StatsSeries.delta(k.avgQuality, k.avgQualityPrev), "", Modifier.weight(1f))
    }

    ChartCard(stringResource(R.string.stats_daily)) {
        DailyBarsChart(StatsSeries.bars(stats), stringResource(R.string.stats_daily_summary, k.reps))
    }
    val cumulative = StatsSeries.cumulative(stats)
    ChartCard(stringResource(R.string.stats_cumulative)) {
        CumulativeChart(cumulative, StatsSeries.milestonesReached(stats),
            stringResource(R.string.stats_cumulative_summary, cumulative.lastOrNull()?.value ?: 0))
    }
    if (stats.wakes.isNotEmpty()) {
        val done = stats.wakes.count { it.status == "succeeded" }
        ChartCard(stringResource(R.string.stats_wake_times), stringResource(R.string.stats_wake_times_caption)) {
            WakeTimesChart(stats.wakes, stringResource(R.string.stats_wake_summary, done, stats.wakes.size))
        }
    }
    val sets = StatsSeries.bestSets(stats)
    if (sets.isNotEmpty()) {
        ChartCard(stringResource(R.string.stats_best_set), stringResource(R.string.stats_best_set_caption)) {
            BestSetChart(sets, stringResource(R.string.stats_best_set_summary, sets.maxOf { it.value }))
        }
    }
    val cells = StatsSeries.heatmap(stats, stats.to)
    ChartCard(stringResource(R.string.stats_activity)) {
        HeatmapChart(cells, stringResource(R.string.stats_activity_summary, cells.count { it.reps > 0 }))
    }
    RecordsCard(stats.records)
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = MinTouchTarget)
            .clip(RoundedCornerShape(RadiusTokens.L))
            .background(ColorTokens.BgSurface.resolve())
            .clickable(role = Role.Button, onClick = onAchievements)
            .padding(SpacingTokens.Ml),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        TokenText(stringResource(R.string.stats_achievements), TypographyTokens.TitleS, modifier = Modifier.weight(1f))
        TokenText("${stats.achievements.unlocked} / ${stats.achievements.total}  ›", TypographyTokens.BodyS,
            color = ColorTokens.TextSecondary.resolve())
    }
}

@Composable
private fun LevelCard(level: StatsData.Level) {
    PushlyCard(Modifier.semantics(mergeDescendants = true) {}) {
        Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.Sm)) {
            Row(verticalAlignment = Alignment.Bottom) {
                TokenText(stringResource(R.string.stats_level, level.level), TypographyTokens.DisplayM, modifier = Modifier.weight(1f))
                TokenText(stringResource(R.string.stats_xp, level.xp), TypographyTokens.BodyS, color = ColorTokens.BrandVoltText.resolve())
            }
            GradientProgressBar(level.fraction, height = 10.dp)
            TokenText(stringResource(R.string.stats_xp_to_next, level.xpForNext - level.xpIntoLevel, level.level + 1),
                TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
        }
    }
}

@Composable
private fun StatTile(label: String, value: String, delta: Int?, unit: String, modifier: Modifier = Modifier) {
    PushlyCard(modifier.semantics(mergeDescendants = true) {}, padding = SpacingTokens.M) {
        Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
            TokenText(label, TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
            TokenText(value, TypographyTokens.Stat, maxLines = 1)
            if (delta != null && delta != 0) {
                val up = delta > 0
                TokenText(
                    stringResource(if (up) R.string.stats_delta_up else R.string.stats_delta_down, abs(delta), unit),
                    TypographyTokens.Caption,
                    color = if (up) ColorTokens.StateSuccessText.resolve() else ColorTokens.StateDanger.resolve(),
                )
            } else {
                TokenText(" ", TypographyTokens.Caption)
            }
        }
    }
}

@Composable
private fun ChartCard(title: String, caption: String? = null, content: @Composable () -> Unit) {
    PushlyCard {
        Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                TokenText(title, TypographyTokens.TitleS)
                caption?.let { TokenText(it, TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve()) }
            }
            content()
        }
    }
}

@Composable
private fun RecordsCard(r: StatsData.Records) {
    PushlyCard {
        Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
            TokenText(stringResource(R.string.stats_records), TypographyTokens.TitleS)
            Row {
                Record(stringResource(R.string.stats_record_best_set), r.bestSet, Modifier.weight(1f))
                Record(stringResource(R.string.stats_record_day), r.maxDay, Modifier.weight(1f))
            }
            Row {
                Record(stringResource(R.string.stats_record_streak), r.bestStreak, Modifier.weight(1f))
                Record(stringResource(R.string.stats_record_all_time), r.repsAllTime, Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun Record(label: String, value: Int, modifier: Modifier = Modifier) {
    Column(modifier.semantics(mergeDescendants = true) {}) {
        TokenText("$value", TypographyTokens.TitleL)
        TokenText(label, TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
    }
}

/** All achievements by group (doc 10 §4): unlocked in their tier colour, locked dimmed with a lock. */
@Composable
fun AchievementsScreen(vm: StatsViewModel, onBack: () -> Unit, modifier: Modifier = Modifier) {
    val s by vm.state.collectAsStateWithLifecycle()
    LaunchedEffect(vm) { vm.start() }
    ArenaBackground(modifier, glow = ColorTokens.LeagueGold, glowOffset = DpOffset(0.dp, (-260).dp)) {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(SpacingTokens.L),
            verticalArrangement = Arrangement.spacedBy(SpacingTokens.L),
        ) {
            TextButton(onClick = onBack, modifier = Modifier.heightIn(min = MinTouchTarget)) {
                Text(stringResource(R.string.stats_back), color = ColorTokens.BrandFlameText.resolve())
            }
            ScreenTitle(stringResource(R.string.stats_achievements), token = TypographyTokens.DisplayM)
            if (s.achievements.isEmpty()) {
                Box(Modifier.fillMaxWidth().heightIn(min = 200.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = ColorTokens.BrandFlame.resolve())
                }
            }
            s.groups.forEach { group ->
                SectionLabel(group.group.replaceFirstChar { it.uppercase() })
                group.items.chunked(3).forEach { row ->
                    Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
                        row.forEach { AchievementBadge(it, Modifier.weight(1f)) }
                        repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
                    }
                }
            }
        }
    }
}

@Composable
private fun AchievementBadge(item: AchievementItem, modifier: Modifier = Modifier) {
    val tier = tierColor(item.tier).resolve()
    val state = stringResource(if (item.unlocked) R.string.stats_unlocked else R.string.stats_locked)
    Column(
        modifier
            .clip(RoundedCornerShape(RadiusTokens.L))
            .background(ColorTokens.BgSurface.resolve())
            .padding(SpacingTokens.Sm)
            .heightIn(min = 170.dp)
            .semantics(mergeDescendants = true) { stateDescription = state },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(SpacingTokens.S),
    ) {
        Box(
            Modifier
                .size(64.dp)
                .clip(CircleShape)
                .background(if (item.unlocked) tier.copy(alpha = 0.18f) else ColorTokens.BgElevated.resolve())
                .border(2.dp, if (item.unlocked) tier else ColorTokens.StrokeSubtle.resolve(), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            TokenText(
                if (item.unlocked) achievementGlyph(item.icon) else "🔒",
                TypographyTokens.TitleM,
                color = if (item.unlocked) tier else ColorTokens.TextDisabled.resolve(),
            )
        }
        TokenText(item.title, TypographyTokens.BodyS, textAlign = TextAlign.Center, maxLines = 2,
            color = if (item.unlocked) ColorTokens.TextPrimary.resolve() else ColorTokens.TextSecondary.resolve())
        TokenText(item.description, TypographyTokens.Caption, textAlign = TextAlign.Center, maxLines = 3,
            color = ColorTokens.TextTertiary.resolve())
    }
}
