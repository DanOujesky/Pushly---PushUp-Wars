package app.pushly.feature.battle

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import app.pushly.core.designsystem.Avatar
import app.pushly.core.designsystem.GradientProgressBar
import app.pushly.core.designsystem.MinTouchTarget
import app.pushly.core.designsystem.Pill
import app.pushly.core.designsystem.SectionLabel
import app.pushly.core.designsystem.TokenText
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.RadiusTokens
import app.pushly.core.designsystem.generated.SpacingTokens
import app.pushly.core.designsystem.generated.TypographyTokens
import app.pushly.core.designsystem.resolve

/**
 * Trophy road (D-076): Clash-Royale-style path from Legend at the top down to Bronze III. The road is gold as far as
 * you have climbed; each league opens with a gate card; "You are here" sits on your rung. Same as iOS `LeagueRoadSheet`.
 */
@Composable
internal fun TrophyRoadSheet(arena: ArenaStatus?, player: BattlePlayer?, frame: String?, onClose: () -> Unit) {
    val trophies = arena?.trophies ?: 0
    val current = LeagueLadder.rungFor(trophies)
    val here = remember { BringIntoViewRequester() }
    HubSheetFrame(stringResource(R.string.ladder_title), onClose) {
        RoadHeader(arena, current, trophies)
        val targets = arena?.targets.orEmpty()
        if (targets.isNotEmpty()) {
            SectionLabel(stringResource(R.string.ladder_above))
            targets.forEach { t ->
                Row(Modifier.fillMaxWidth().heightIn(min = MinTouchTarget).clip(RoundedCornerShape(RadiusTokens.S))
                    .background(ColorTokens.BgSurface.resolve()).padding(horizontal = SpacingTokens.M)
                    .semantics(mergeDescendants = true) {},
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Sm)) {
                    Avatar(t.username, t.avatarPreset, size = 32.dp)
                    TokenText(t.username, TypographyTokens.BodyS, Modifier.weight(1f), maxLines = 1)
                    TokenText("${t.trophies} 🏆", TypographyTokens.BodyS)
                    TokenText("+${t.gap}", TypographyTokens.Caption, color = ColorTokens.BrandFlameText.resolve())
                }
            }
        }
        SectionLabel(stringResource(R.string.ladder_all))
        Column {
            LeagueLadder.rungs.asReversed().forEachIndexed { i, rung ->
                val isCurrent = rung == current
                RoadStop(
                    rung, trophies, isCurrent, top = i == 0, bottom = i == LeagueLadder.rungs.lastIndex,
                    player = player, frame = frame,
                    modifier = if (isCurrent) Modifier.bringIntoViewRequester(here) else Modifier,
                )
            }
        }
        SectionLabel(stringResource(R.string.ladder_how))
        listOf(R.string.ladder_floors, R.string.ladder_season, R.string.ladder_only_quick).forEach {
            TokenText("• " + stringResource(it), TypographyTokens.Caption, color = ColorTokens.TextSecondary.resolve())
        }
    }
    LaunchedEffect(Unit) { runCatching { here.bringIntoView() } }
}

@Composable
private fun RoadHeader(arena: ArenaStatus?, current: LeagueLadder.Rung, trophies: Int) {
    val color = leagueColor(current.league).resolve()
    val shape = RoundedCornerShape(RadiusTokens.L)
    Column(
        Modifier.fillMaxWidth().clip(shape)
            .background(Brush.verticalGradient(listOf(color.copy(alpha = 0.30f), ColorTokens.BgSurface.resolve())))
            .border(1.dp, color.copy(alpha = 0.5f), shape)
            .padding(SpacingTokens.L)
            .semantics(mergeDescendants = true) {},
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(SpacingTokens.S),
    ) {
        GateBadge(current.league, current.tier, reached = true, size = 72)
        TokenText(leagueName(current.league, current.tier), TypographyTokens.TitleL, color = color)
        TokenText("🏆 $trophies", TypographyTokens.DisplayM, color = ColorTokens.LeagueGold.resolve())
        val to = current.to
        if (to != null) {
            GradientProgressBar((trophies - current.from).toFloat() / maxOf(to + 1 - current.from, 1), Modifier.fillMaxWidth(), height = 10.dp)
            TokenText(stringResource(R.string.ladder_to_go, to + 1 - trophies), TypographyTokens.Caption, color = ColorTokens.TextSecondary.resolve())
        }
        if (arena != null) {
            Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                Pill(stringResource(R.string.ladder_best, arena.bestTrophies), color = ColorTokens.LeagueGold)
                arena.rank?.let { Pill(stringResource(R.string.hub_rank, it), color = ColorTokens.BrandFlameText) }
            }
        }
    }
}

/** A small shield-coloured disc with the league glyph; dimmed until reached. */
@Composable
private fun GateBadge(league: String, tier: String?, reached: Boolean, size: Int) {
    val color = leagueColor(league).resolve()
    Box(
        Modifier.size(size.dp).clip(CircleShape)
            .background(Brush.radialGradient(listOf(color.copy(alpha = if (reached) 0.9f else 0.35f), color.copy(alpha = 0.15f))))
            .border(2.dp, Color.White.copy(alpha = if (reached) 0.45f else 0.15f), CircleShape)
            .clearAndSetSemantics {},
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            TokenText(leagueGlyph(league), if (size >= 60) TypographyTokens.DisplayM else TypographyTokens.TitleL,
                color = Color.White.copy(alpha = if (reached) 1f else 0.5f))
            if (tier != null && size >= 60) TokenText(tier, TypographyTokens.TitleS, color = Color.White)
        }
    }
}

@Composable
private fun RoadStop(
    rung: LeagueLadder.Rung,
    trophies: Int,
    isCurrent: Boolean,
    top: Boolean,
    bottom: Boolean,
    player: BattlePlayer?,
    frame: String?,
    modifier: Modifier = Modifier,
) {
    val reached = rung.from <= trophies
    // the road above this stop is covered once the next rung up is reached
    val aboveCovered = rung.to?.let { trophies > it } ?: false
    val gold = ColorTokens.LeagueGold.resolve()
    val dim = Color.White.copy(alpha = 0.12f)
    val color = leagueColor(rung.league).resolve()
    val gate = rung.tier == null || rung.tier == "III"
    Row(modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
        Box(Modifier.width(36.dp).fillMaxHeight(), contentAlignment = Alignment.Center) {
            Canvas(Modifier.fillMaxHeight().width(36.dp)) {
                val x = size.width / 2
                val w = 6.dp.toPx()
                if (!top) drawLine(if (aboveCovered) gold else dim, Offset(x, 0f), Offset(x, size.height / 2), w)
                if (!bottom) drawLine(if (reached) gold else dim, Offset(x, size.height / 2), Offset(x, size.height), w)
            }
            val node = if (gate) 22.dp else 14.dp
            Box(Modifier.size(node).clip(CircleShape).background(if (reached) gold else ColorTokens.BgElevated.resolve())
                .border(2.dp, if (isCurrent) Color.White else color.copy(alpha = 0.7f), CircleShape))
        }
        val shape = RoundedCornerShape(RadiusTokens.M)
        Row(
            Modifier.weight(1f).padding(vertical = if (gate) SpacingTokens.S else SpacingTokens.Xs)
                .heightIn(min = MinTouchTarget).clip(shape)
                .background(
                    when {
                        isCurrent -> Brush.horizontalGradient(listOf(color.copy(alpha = 0.35f), color.copy(alpha = 0.10f)))
                        gate -> Brush.horizontalGradient(listOf(color.copy(alpha = if (reached) 0.22f else 0.10f), ColorTokens.BgSurface.resolve()))
                        else -> Brush.horizontalGradient(listOf(ColorTokens.BgSurface.resolve(), ColorTokens.BgSurface.resolve()))
                    },
                )
                .border(if (isCurrent) 2.dp else 1.dp, if (isCurrent) color else Color.White.copy(alpha = 0.06f), shape)
                .padding(horizontal = SpacingTokens.M, vertical = SpacingTokens.S)
                .semantics(mergeDescendants = true) {},
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Sm),
        ) {
            if (gate) GateBadge(rung.league, rung.tier, reached, 44)
            Column(Modifier.weight(1f)) {
                TokenText(leagueName(rung.league, rung.tier), if (gate) TypographyTokens.TitleM else TypographyTokens.TitleS,
                    color = if (isCurrent || (gate && reached)) color else if (reached) ColorTokens.TextPrimary.resolve() else ColorTokens.TextTertiary.resolve())
                val range = if (rung.to != null) "${rung.from}–${rung.to} 🏆" else "${rung.from}+ 🏆"
                TokenText(range, TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
                if (rung.from in LeagueLadder.FLOORS) {
                    TokenText("🛡 " + stringResource(R.string.ladder_safe_floor), TypographyTokens.Caption, color = ColorTokens.BrandCyan.resolve())
                }
                val to = rung.to
                if (isCurrent && to != null) {
                    GradientProgressBar((trophies - rung.from).toFloat() / maxOf(to + 1 - rung.from, 1),
                        Modifier.fillMaxWidth().padding(top = SpacingTokens.Xs), height = 6.dp)
                }
            }
            when {
                isCurrent -> Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    if (player != null) Avatar(player.username, player.avatarPreset, size = 32.dp, frame = frame)
                    TokenText(stringResource(R.string.ladder_here), TypographyTokens.Caption, color = ColorTokens.BrandFlameText.resolve())
                }
                reached -> TokenText("✓", TypographyTokens.TitleS, color = ColorTokens.StateSuccessText.resolve())
                else -> TokenText("🔒 ${rung.from - trophies}", TypographyTokens.Caption, color = ColorTokens.TextSecondary.resolve())
            }
        }
    }
}
