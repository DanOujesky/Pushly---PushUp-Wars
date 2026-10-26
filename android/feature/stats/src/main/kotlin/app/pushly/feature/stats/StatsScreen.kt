package app.pushly.feature.stats

import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import app.pushly.core.designsystem.AdBannerSlot
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
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import app.pushly.core.designsystem.Avatar
import app.pushly.core.designsystem.Pill
import app.pushly.core.designsystem.PrimaryButton
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap

/** Stats sections (D-077): Battles · Push-ups · Achievements. Same as iOS `StatsView.Section`. */
enum class StatsSection { Battles, Pushups, Badges }

/**
 * Profile → Stats (doc 10 §2, D-067, D-077): Battles (trophies, league, rank, record ring, trophy history, players to
 * beat), Push-ups (period, level, KPI tiles, charts, records) and Achievements (progress + every badge).
 */
@Composable
fun StatsScreen(
    vm: StatsViewModel,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    onFight: (() -> Unit)? = null,
    initialSection: StatsSection = StatsSection.Battles,
) {
    val s by vm.state.collectAsStateWithLifecycle()
    var section by rememberSaveable { mutableStateOf(initialSection) }
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
            Segmented(
                listOf(
                    StatsSection.Battles to stringResource(R.string.stats_section_battles),
                    StatsSection.Pushups to stringResource(R.string.stats_section_pushups),
                    StatsSection.Badges to stringResource(R.string.stats_section_badges),
                ),
                section,
            ) { section = it }
            when (section) {
                StatsSection.Battles -> {
                    val b = s.battle
                    if (b != null) {
                        TrophySection(b, onFight)
                    } else {
                        Box(Modifier.fillMaxWidth().heightIn(min = 200.dp), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator(color = ColorTokens.BrandFlame.resolve())
                        }
                    }
                }
                StatsSection.Pushups -> {
                    PeriodPicker(s.period, vm::selectPeriod)
                    val stats = s.stats
                    when {
                        stats != null -> StatsContent(stats)
                        s.failed -> {
                            InlineBanner(stringResource(R.string.stats_failed), kind = BannerKind.Warning)
                            TextButton(onClick = vm::reload) { Text(stringResource(R.string.stats_retry)) }
                        }
                        else -> Box(Modifier.fillMaxWidth().heightIn(min = 200.dp), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator(color = ColorTokens.BrandFlame.resolve())
                        }
                    }
                }
                StatsSection.Badges -> AchievementsGrid(s)
            }
            // below the charts (doc 13 §1)
            AdBannerSlot("stats_banner")
        }
    }
}

@Composable
private fun <T> Segmented(options: List<Pair<T, String>>, selected: T, onSelect: (T) -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(RadiusTokens.M)).background(ColorTokens.BgSurface.resolve()).padding(4.dp),
    ) {
        options.forEach { (value, label) ->
            val on = value == selected
            Box(
                Modifier
                    .weight(1f)
                    .heightIn(min = MinTouchTarget)
                    .clip(RoundedCornerShape(RadiusTokens.S))
                    .background(if (on) ColorTokens.BgElevated.resolve() else ColorTokens.BgSurface.resolve())
                    .selectable(on, role = Role.Tab) { onSelect(value) },
                contentAlignment = Alignment.Center,
            ) {
                TokenText(label, TypographyTokens.BodyS, maxLines = 1,
                    color = if (on) ColorTokens.TextPrimary.resolve() else ColorTokens.TextTertiary.resolve())
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
private fun StatsContent(stats: StatsData) {
    LevelCard(stats.progress)
    val k = stats.kpis
    Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
        StatTile(stringResource(R.string.stats_kpi_reps), "${k.reps}", StatsSeries.delta(k.reps, k.repsPrev), "", Modifier.weight(1f))
        StatTile(stringResource(R.string.stats_kpi_best_set), "${k.bestSet}", StatsSeries.delta(k.bestSet, k.bestSetPrev), "", Modifier.weight(1f))
    }
    Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
        StatTile(stringResource(R.string.stats_kpi_form), k.avgQuality?.toString() ?: "–",
            StatsSeries.delta(k.avgQuality, k.avgQualityPrev), "", Modifier.weight(1f))
        StatTile(stringResource(R.string.stats_kpi_all_time), "${stats.records.repsAllTime}", null, "", Modifier.weight(1f))
    }

    ChartCard(stringResource(R.string.stats_daily)) {
        DailyBarsChart(StatsSeries.bars(stats), stringResource(R.string.stats_daily_summary, k.reps))
    }
    val cumulative = StatsSeries.cumulative(stats)
    ChartCard(stringResource(R.string.stats_cumulative)) {
        CumulativeChart(cumulative, StatsSeries.milestonesReached(stats),
            stringResource(R.string.stats_cumulative_summary, cumulative.lastOrNull()?.value ?: 0))
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
            AchievementsGrid(s)
        }
    }
}

/** Progress header + every badge by group, unlocked first (D-077). */
@Composable
private fun AchievementsGrid(s: StatsViewModel.UiState) {
    Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.L)) {
        if (s.achievements.isNotEmpty()) {
            val unlocked = s.achievements.count { it.unlocked }
            Card {
                Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                    TokenText("$unlocked", TypographyTokens.DisplayM, color = ColorTokens.LeagueGold.resolve())
                    TokenText("/ ${s.achievements.size}", TypographyTokens.TitleM, color = ColorTokens.TextTertiary.resolve(),
                        modifier = Modifier.weight(1f))
                    TokenText(stringResource(R.string.stats_unlocked_of), TypographyTokens.Caption, color = ColorTokens.TextSecondary.resolve())
                }
                GradientProgressBar(unlocked.toFloat() / maxOf(s.achievements.size, 1), Modifier.fillMaxWidth(), height = 10.dp)
            }
        } else {
            Box(Modifier.fillMaxWidth().heightIn(min = 200.dp), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = ColorTokens.BrandFlame.resolve())
            }
        }
        s.groups.forEach { group ->
            SectionLabel(group.group.replaceFirstChar { it.uppercase() })
            (group.items.filter { it.unlocked } + group.items.filter { !it.unlocked }).chunked(3).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
                    row.forEach { AchievementBadge(it, Modifier.weight(1f)) }
                    repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }
    }
}

@Composable
internal fun AchievementBadge(item: AchievementItem, modifier: Modifier = Modifier) {
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

@Composable
private fun Card(content: @Composable ColumnScope.() -> Unit) {
    PushlyCard(Modifier.fillMaxWidth()) {
        Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.Sm), content = content)
    }
}

/** The main part of Stats (D-067): trophies, league, the next step, rank, players right above, record, history. */
@Composable
private fun TrophySection(b: BattleStats, onFight: (() -> Unit)?) {
    Card {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
            TokenText(BattleStats.glyph(b.league), TypographyTokens.DisplayL, modifier = Modifier.clearAndSetSemantics {})
            Column(Modifier.weight(1f)) {
                TokenText("${b.trophies} 🏆", TypographyTokens.DisplayL)
                TokenText(leagueLabel(b.league, b.tier), TypographyTokens.TitleS, color = ColorTokens.LeagueGold.resolve())
            }
            b.rank?.let { rank ->
                Column(horizontalAlignment = Alignment.End) {
                    TokenText("#$rank", TypographyTokens.Stat, color = ColorTokens.BrandFlameText.resolve())
                    TokenText(stringResource(R.string.stats_in_world), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
                }
            }
        }
        GradientProgressBar(b.progressToNext.toFloat(), Modifier.fillMaxWidth())
        Row {
            val n = b.next
            TokenText(
                if (n != null) stringResource(R.string.stats_to_next, n.at - b.trophies, leagueLabel(n.league, n.tier)) else stringResource(R.string.stats_top_league),
                TypographyTokens.Caption,
                color = ColorTokens.TextSecondary.resolve(),
                modifier = Modifier.weight(1f),
            )
            b.seasonDaysLeft()?.let { TokenText(stringResource(R.string.stats_season_ends, it), TypographyTokens.Caption, color = ColorTokens.TextSecondary.resolve()) }
        }
        TokenText(stringResource(R.string.stats_best_ever, b.bestTrophies), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
    }
    if (onFight != null) PrimaryButton(stringResource(R.string.stats_fight), onFight)
    if (b.targets.isNotEmpty()) {
        Card {
            TokenText(stringResource(R.string.stats_targets), TypographyTokens.TitleS)
            b.targets.forEach { t ->
                val a11y = stringResource(R.string.stats_target_a11y, t.username, t.gap)
                Row(
                    Modifier.fillMaxWidth().heightIn(min = MinTouchTarget).clearAndSetSemantics { contentDescription = a11y },
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S),
                ) {
                    Avatar(t.username, t.avatarPreset, size = 32.dp)
                    TokenText(t.username, TypographyTokens.BodyS, modifier = Modifier.weight(1f))
                    TokenText("${t.trophies} 🏆", TypographyTokens.BodyS)
                    TokenText("+${t.gap}", TypographyTokens.Caption, color = ColorTokens.BrandFlameText.resolve())
                }
            }
            TokenText(stringResource(R.string.stats_targets_hint), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
        }
    }
    RecordRing(b.record)
    if (b.history.size > 1) {
        ChartCard(stringResource(R.string.stats_trophies_chart), stringResource(R.string.stats_trophies_caption)) {
            TrophyChart(b.history.map { it.trophies } + b.history.last().trophies)
        }
    }
    if (b.recent.isNotEmpty()) {
        Card {
            TokenText(stringResource(R.string.stats_recent), TypographyTokens.TitleS)
            b.recent.forEach { x ->
                Row(Modifier.fillMaxWidth().heightIn(min = MinTouchTarget).semantics(mergeDescendants = true) {},
                    verticalAlignment = Alignment.CenterVertically) {
                    val color = when (x.result) {
                        "win" -> ColorTokens.StateSuccessText
                        "loss" -> ColorTokens.StateDanger
                        else -> ColorTokens.TextSecondary
                    }
                    TokenText(when (x.result) { "win" -> "W"; "loss" -> "L"; else -> "D" }, TypographyTokens.TitleS, color = color.resolve(),
                        modifier = Modifier.width(24.dp))
                    TokenText(x.opponent, TypographyTokens.BodyS, modifier = Modifier.weight(1f))
                    val d = x.delta
                    if (d != null && x.ranked) {
                        TokenText(if (d >= 0) "+$d 🏆" else "$d 🏆", TypographyTokens.BodyS,
                            color = (if (d >= 0) ColorTokens.StateSuccessText else ColorTokens.StateDanger).resolve())
                    } else {
                        TokenText(stringResource(R.string.stats_friendly), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
                    }
                }
            }
        }
    }
}

/** Win-rate ring with W / L / D and streaks (D-077). Same as iOS. */
@Composable
private fun RecordRing(r: BattleStats.Record) {
    val rate = if (r.played == 0) 0f else r.wins.toFloat() / r.played
    val track = Color.White.copy(alpha = 0.08f)
    val ring = Brush.linearGradient(listOf(ColorTokens.StateSuccess.resolve(), ColorTokens.BrandLime.resolve()))
    Card {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.L),
            modifier = Modifier.semantics(mergeDescendants = true) {}) {
            Box(Modifier.size(96.dp), contentAlignment = Alignment.Center) {
                Canvas(Modifier.fillMaxSize()) {
                    val w = 10.dp.toPx()
                    drawArc(track, 0f, 360f, false, style = Stroke(w))
                    drawArc(ring, -90f, 360f * rate, false, style = Stroke(w, cap = StrokeCap.Round))
                }
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    TokenText(r.winRate?.let { "$it%" } ?: "–", TypographyTokens.TitleL)
                    TokenText(stringResource(R.string.stats_win_rate_short), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
                    Tally(r.wins, "W", ColorTokens.StateSuccessText.resolve())
                    Tally(r.losses, "L", ColorTokens.StateDanger.resolve())
                    Tally(r.draws, "D", ColorTokens.TextSecondary.resolve())
                }
                TokenText(stringResource(R.string.stats_battles_played, r.played), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
                Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                    Pill(stringResource(R.string.stats_streak_now, r.winStreak), color = ColorTokens.BrandFlameText)
                    Pill(stringResource(R.string.stats_streak_best, r.bestWinStreak), color = ColorTokens.LeagueGold)
                }
            }
        }
    }
}

@Composable
private fun Tally(n: Int, letter: String, color: Color) {
    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        TokenText("$n", TypographyTokens.Stat, color = color)
        TokenText(letter, TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
    }
}

@Composable
internal fun leagueLabel(league: String, tier: String?): String {
    val name = stringResource(
        when (league) {
            "bronze" -> R.string.league_bronze
            "silver" -> R.string.league_silver
            "gold" -> R.string.league_gold
            "platinum" -> R.string.league_platinum
            "diamond" -> R.string.league_diamond
            "champion" -> R.string.league_champion
            else -> R.string.league_legend
        },
    )
    return if (tier != null) "$name $tier" else name
}

/** Trophy balance over time (step line, oldest → now). */
@Composable
private fun TrophyChart(values: List<Int>) {
    val color = ColorTokens.LeagueGold.resolve()
    val lo = values.minOrNull() ?: 0
    val hi = maxOf(values.maxOrNull() ?: 1, lo + 1)
    val a11y = stringResource(R.string.stats_trophies_summary, values.firstOrNull() ?: 0, values.lastOrNull() ?: 0)
    Canvas(Modifier.fillMaxWidth().height(160.dp).clearAndSetSemantics { contentDescription = a11y }) {
        if (values.size < 2) return@Canvas
        val step = size.width / (values.size - 1)
        fun y(v: Int) = size.height - (v - lo).toFloat() / (hi - lo) * size.height * 0.9f - size.height * 0.05f
        val path = Path().apply {
            moveTo(0f, y(values[0]))
            for (i in 1 until values.size) {
                lineTo(i * step, y(values[i - 1]))
                lineTo(i * step, y(values[i]))
            }
        }
        drawPath(path, color, style = Stroke(width = 3.dp.toPx()))
    }
}
