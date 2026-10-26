package app.pushly.feature.battle

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.pushly.core.designsystem.Avatar
import app.pushly.core.designsystem.Pill
import app.pushly.core.designsystem.SectionLabel
import app.pushly.core.designsystem.TokenText
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.RadiusTokens
import app.pushly.core.designsystem.generated.SpacingTokens
import app.pushly.core.designsystem.generated.TokenColor
import app.pushly.core.designsystem.generated.TypographyTokens
import app.pushly.core.designsystem.resolve
import app.pushly.core.designsystem.toTextStyle
import androidx.compose.ui.unit.sp
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

/**
 * Battle history (D-077): a record card (win rate, last 10, streak, close calls, trophies) and every battle as a match
 * card — VICTORY / DEFEAT, the final score face to face, by how much it was decided ("Lost by 1 push-up") and a
 * SO CLOSE / CLUTCH tag for nail-biters. Grouped by day; past seasons at the end. Same as iOS.
 */
@Composable
internal fun HistorySheet(s: BattleHubViewModel.UiState, player: BattlePlayer?, frame: String?, onClose: () -> Unit) {
    HubSheetFrame(stringResource(R.string.history_title), onClose) {
        RecordCard(HistorySummary.of(s.history), s.arena?.record)
        if (s.history.isEmpty()) {
            Column(Modifier.fillMaxWidth().padding(vertical = SpacingTokens.Xl), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                TokenText("⚔️", TypographyTokens.DisplayM, modifier = Modifier.clearAndSetSemantics {})
                TokenText(stringResource(R.string.history_empty_title), TypographyTokens.TitleM)
                TokenText(stringResource(R.string.history_empty_body), TypographyTokens.Caption, color = ColorTokens.TextSecondary.resolve(),
                    textAlign = TextAlign.Center)
            }
        }
        var lastDay: String? = null
        s.history.forEach { b ->
            val day = dayLabel(b.endedAt ?: b.createdAt)
            if (day != lastDay) {
                SectionLabel(day)
                lastDay = day
            }
            MatchCard(b, BattleRecap.of(b), player, frame)
        }
        if (s.seasons.isNotEmpty()) {
            SectionLabel(stringResource(R.string.battle_seasons))
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Sm)) {
                s.seasons.forEach { SeasonCard(it) }
            }
        }
    }
}

private fun instant(iso: String?): ZonedDateTime? =
    iso?.let { runCatching { OffsetDateTime.parse(it).atZoneSameInstant(ZoneId.systemDefault()) }.getOrNull() }

@Composable
private fun dayLabel(iso: String?): String {
    val d = instant(iso) ?: return stringResource(R.string.history_earlier)
    val today = LocalDate.now(ZoneId.systemDefault())
    return when (d.toLocalDate()) {
        today -> stringResource(R.string.history_today)
        today.minusDays(1) -> stringResource(R.string.history_yesterday)
        else -> d.format(DateTimeFormatter.ofPattern("EEEE d MMMM", Locale.getDefault()))
    }
}

private fun outcomeColor(o: BattleRecap.Outcome): TokenColor = when (o) {
    BattleRecap.Outcome.Win -> ColorTokens.StateSuccessText
    BattleRecap.Outcome.Loss -> ColorTokens.StateDanger
    BattleRecap.Outcome.Draw -> ColorTokens.TextSecondary
}

@Composable
private fun RecordCard(summary: HistorySummary, record: ArenaStatus.Record?) {
    val wins = record?.wins ?: summary.wins
    val losses = record?.losses ?: summary.losses
    val draws = record?.draws ?: summary.draws
    val played = wins + losses + draws
    val rate = if (played == 0) 0f else wins.toFloat() / played
    val track = Color.White.copy(alpha = 0.08f)
    val ring = Brush.linearGradient(listOf(ColorTokens.StateSuccess.resolve(), ColorTokens.BrandLime.resolve()))
    val shape = RoundedCornerShape(RadiusTokens.L)
    Column(
        Modifier.fillMaxWidth().clip(shape)
            .background(Brush.linearGradient(listOf(ColorTokens.BrandFlame.resolve().copy(alpha = 0.18f), ColorTokens.BgSurface.resolve())))
            .border(1.dp, ColorTokens.StrokeSubtle.resolve(), shape)
            .padding(SpacingTokens.Ml)
            .semantics(mergeDescendants = true) {},
        verticalArrangement = Arrangement.spacedBy(SpacingTokens.M),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.L)) {
            Box(Modifier.size(96.dp), contentAlignment = Alignment.Center) {
                Canvas(Modifier.fillMaxSize()) {
                    val w = 10.dp.toPx()
                    drawArc(track, 0f, 360f, false, style = Stroke(w))
                    drawArc(ring, -90f, 360f * rate, false, style = Stroke(w, cap = StrokeCap.Round))
                }
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    TokenText(if (played == 0) "–" else "${(rate * 100).toInt()}%", TypographyTokens.TitleL)
                    TokenText(stringResource(R.string.history_win_rate), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
                    Tally(wins, "W", ColorTokens.StateSuccessText)
                    Tally(losses, "L", ColorTokens.StateDanger)
                    Tally(draws, "D", ColorTokens.TextSecondary)
                }
                if (summary.form.isNotEmpty()) {
                    TokenText(stringResource(R.string.history_last_n, summary.form.size), TypographyTokens.Caption,
                        color = ColorTokens.TextTertiary.resolve())
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        // oldest → newest, newest on the right
                        summary.form.asReversed().forEach { o ->
                            Box(Modifier.size(14.dp).clip(RoundedCornerShape(3.dp)).background(outcomeColor(o).resolve()),
                                contentAlignment = Alignment.Center) {
                                TokenText(when (o) { BattleRecap.Outcome.Win -> "W"; BattleRecap.Outcome.Loss -> "L"; else -> "D" },
                                    TypographyTokens.Caption, color = Color.Black.copy(alpha = 0.6f),
                                    style = TypographyTokens.Caption.toTextStyle().copy(fontSize = 8.sp))
                            }
                        }
                    }
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
            if (record != null && record.winStreak > 1) Pill(stringResource(R.string.history_streak, record.winStreak), color = ColorTokens.BrandFlameText)
            if (record != null && record.bestWinStreak > 0) Pill(stringResource(R.string.history_best_streak, record.bestWinStreak), color = ColorTokens.TextSecondary)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
            if (summary.clutchWins > 0) Pill(stringResource(R.string.history_clutch, summary.clutchWins), color = ColorTokens.BrandVoltText)
            if (summary.closeLosses > 0) Pill(stringResource(R.string.history_so_close, summary.closeLosses), color = ColorTokens.StateWarning)
            if (summary.trophyNet != 0) {
                Pill(stringResource(R.string.history_trophies_recent, if (summary.trophyNet > 0) "+${summary.trophyNet}" else "${summary.trophyNet}"),
                    color = if (summary.trophyNet > 0) ColorTokens.LeagueGold else ColorTokens.StateDanger)
            }
        }
    }
}

@Composable
private fun Tally(n: Int, letter: String, color: TokenColor) {
    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        TokenText("$n", TypographyTokens.Stat, color = color.resolve())
        TokenText(letter, TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
    }
}

@Composable
private fun recapLine(r: BattleRecap): String {
    val won = r.outcome == BattleRecap.Outcome.Win
    return when (val m = r.margin) {
        is BattleRecap.Margin.Reps -> when {
            m.n == 1 -> stringResource(if (won) R.string.history_won_by_one else R.string.history_lost_by_one)
            else -> stringResource(if (won) R.string.history_won_by_n else R.string.history_lost_by_n, m.n)
        }
        is BattleRecap.Margin.Time -> stringResource(if (won) R.string.history_won_by_s else R.string.history_lost_by_s,
            String.format(Locale.getDefault(), "%.1f", m.ms / 1000.0))
        is BattleRecap.Margin.Rounds -> stringResource(if (won) R.string.history_won_rounds else R.string.history_lost_rounds, m.mine, m.theirs)
        BattleRecap.Margin.Form -> stringResource(if (won) R.string.history_form_won else R.string.history_form_lost)
        is BattleRecap.Margin.Forfeit -> stringResource(if (m.byMe) R.string.history_you_left else R.string.history_opp_left)
        is BattleRecap.Margin.TurnMissed -> stringResource(if (m.byMe) R.string.history_you_missed else R.string.history_opp_missed)
        BattleRecap.Margin.Draw -> stringResource(R.string.history_line_draw)
        BattleRecap.Margin.Void -> stringResource(R.string.history_line_void)
    }
}

@Composable
private fun MatchCard(b: Battle, r: BattleRecap, player: BattlePlayer?, frame: String?) {
    val tint = outcomeColor(r.outcome).resolve()
    val shape = RoundedCornerShape(RadiusTokens.L)
    val title = when {
        b.status == "void" -> R.string.history_no_result
        r.outcome == BattleRecap.Outcome.Win -> R.string.history_victory
        r.outcome == BattleRecap.Outcome.Loss -> R.string.history_defeat
        else -> R.string.history_draw
    }
    val kind = when {
        b.bot == "arena" -> R.string.history_kind_arena
        b.bot != null -> R.string.history_kind_practice
        b.ranked -> R.string.history_kind_ranked
        else -> R.string.history_kind_friendly
    }
    Row(
        Modifier.fillMaxWidth().height(IntrinsicSize.Min).clip(shape)
            .background(Brush.horizontalGradient(listOf(tint.copy(alpha = if (r.isClose) 0.16f else 0.10f), ColorTokens.BgSurface.resolve())))
            .border(1.dp, if (r.isClose) tint.copy(alpha = 0.5f) else ColorTokens.StrokeSubtle.resolve(), shape)
            .semantics(mergeDescendants = true) {},
    ) {
        Box(Modifier.width(5.dp).fillMaxHeight().background(tint))
        Column(Modifier.padding(SpacingTokens.M), verticalArrangement = Arrangement.spacedBy(SpacingTokens.Sm)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                TokenText(stringResource(title), TypographyTokens.LabelDisplay, color = tint)
                if (r.isClose) {
                    val tag = when (r.outcome) {
                        BattleRecap.Outcome.Win -> R.string.history_tag_clutch
                        BattleRecap.Outcome.Loss -> R.string.history_tag_so_close
                        else -> R.string.history_tag_dead_even
                    }
                    TokenText(stringResource(tag), TypographyTokens.Caption, color = ColorTokens.BgBase.resolve(),
                        modifier = Modifier.clip(CircleShape)
                            .background((if (r.outcome == BattleRecap.Outcome.Loss) ColorTokens.StateWarning else ColorTokens.BrandVolt).resolve())
                            .padding(horizontal = 6.dp, vertical = 2.dp))
                }
                Spacer(Modifier.weight(1f))
                instant(b.endedAt ?: b.createdAt)?.let {
                    TokenText(it.format(DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT)), TypographyTokens.Caption,
                        color = ColorTokens.TextTertiary.resolve())
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                    Column {
                        Avatar(player?.username ?: "?", player?.avatarPreset, size = 34.dp, frame = frame)
                        TokenText(stringResource(R.string.history_you), TypographyTokens.Caption, color = ColorTokens.TextSecondary.resolve(), maxLines = 1)
                    }
                    Score(r.mine, r.mine >= r.theirs)
                }
                TokenText("–", TypographyTokens.TitleL, color = ColorTokens.TextTertiary.resolve())
                Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S, Alignment.End)) {
                    Score(r.theirs, r.theirs >= r.mine)
                    Column(horizontalAlignment = Alignment.End) {
                        Avatar(b.opponent.username, b.opponent.avatarPreset, size = 34.dp)
                        TokenText(b.opponentDisplayName, TypographyTokens.Caption, color = ColorTokens.TextSecondary.resolve(), maxLines = 1,
                            modifier = Modifier.widthIn(max = 110.dp))
                    }
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                TokenText(recapLine(r), TypographyTokens.BodyS, modifier = Modifier.weight(1f))
                val t = b.myTrophies
                if (b.ranked && t != null) {
                    Pill(if (t >= 0) "+$t 🏆" else "$t 🏆", color = if (t >= 0) ColorTokens.LeagueGold else ColorTokens.StateDanger)
                }
            }
            TokenText(modeTitle(b.mode, b.variant) + " · " + stringResource(kind), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
        }
    }
}

@Composable
private fun Score(n: Int, lead: Boolean) {
    TokenText("$n", TypographyTokens.DisplayM, color = (if (lead) ColorTokens.TextPrimary else ColorTokens.TextTertiary).resolve())
}

@Composable
private fun SeasonCard(season: SeasonResult) {
    val color = leagueColor(season.league).resolve()
    val shape = RoundedCornerShape(RadiusTokens.L)
    Column(
        Modifier.width(150.dp).clip(shape).background(ColorTokens.BgSurface.resolve()).border(1.dp, color.copy(alpha = 0.4f), shape)
            .padding(SpacingTokens.M).semantics(mergeDescendants = true) {},
        verticalArrangement = Arrangement.spacedBy(SpacingTokens.Xs),
    ) {
        TokenText(leagueGlyph(season.league), TypographyTokens.DisplayM, modifier = Modifier.clearAndSetSemantics {})
        TokenText(season.month, TypographyTokens.TitleS)
        TokenText(leagueName(season.league, season.tier), TypographyTokens.Caption, color = color)
        TokenText(stringResource(R.string.history_season_best, season.bestTrophies, season.rank), TypographyTokens.Caption,
            color = ColorTokens.TextTertiary.resolve())
    }
}
