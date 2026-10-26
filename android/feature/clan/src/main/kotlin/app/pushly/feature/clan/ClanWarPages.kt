package app.pushly.feature.clan

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.animateIntAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
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
import app.pushly.core.designsystem.Avatar
import app.pushly.core.designsystem.BannerKind
import app.pushly.core.designsystem.ClanEmblem
import app.pushly.core.designsystem.InlineBanner
import app.pushly.core.designsystem.MinTouchTarget
import app.pushly.core.designsystem.Pill
import app.pushly.core.designsystem.ProBadge
import app.pushly.core.designsystem.profileLink
import app.pushly.core.designsystem.ProfileTarget
import androidx.compose.foundation.layout.fillMaxSize
import app.pushly.core.designsystem.SectionLabel
import app.pushly.core.designsystem.SideViewNotice
import app.pushly.core.designsystem.generated.TokenColor
import app.pushly.core.designsystem.TokenText
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.RadiusTokens
import app.pushly.core.designsystem.generated.SpacingTokens
import app.pushly.core.designsystem.generated.TypographyTokens
import app.pushly.core.designsystem.resolve
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// Clan War pages (D-079): the live arena (a Clash-Royale-style race), war history like Battle history, "who pushed"
// per war with points per day, and any clan's page. They open in one sheet with a back button. Same as iOS.

/** A page inside the clan war sheet. */
sealed interface ClanPage {
    data object War : ClanPage
    data object History : ClanPage
    data class Profile(val clanId: String) : ClanPage
    data class Fighters(val warId: String, val clanId: String?) : ClanPage
}

/** One sheet, pages pushed on a stack (back arrow top left). */
@Composable
internal fun ClanNavSheet(vm: ClanViewModel, s: ClanViewModel.UiState, start: ClanPage, onClose: () -> Unit) {
    var stack by remember(start) { mutableStateOf(listOf(start)) }
    val page = stack.last()
    val push: (ClanPage) -> Unit = { stack = stack + it }
    val title = when (page) {
        ClanPage.War -> stringResource(R.string.clan_war)
        ClanPage.History -> stringResource(R.string.clan_war_history)
        is ClanPage.Profile -> stringResource(R.string.clanwar_page_clan)
        is ClanPage.Fighters -> stringResource(R.string.clanwar_who_pushed)
    }
    SheetFrame(title, onClose, scroll = false, onBack = if (stack.size > 1) ({ stack = stack.dropLast(1) }) else null) {
        key(stack.size, page) {
            Column(
                Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(bottom = SpacingTokens.Xl),
                verticalArrangement = Arrangement.spacedBy(SpacingTokens.M),
            ) {
                when (page) {
                    ClanPage.War -> WarPage(vm, s, push)
                    ClanPage.History -> HistoryPage(vm, s, push)
                    is ClanPage.Profile -> ClanProfilePage(vm, page.clanId)
                    is ClanPage.Fighters -> FightersPage(vm, page, push)
                }
            }
        }
    }
}

/** While a war is live: refresh every 15 s so the arena moves (D-079). */
@Composable
internal fun LiveWarPoll(vm: ClanViewModel, live: Boolean) {
    LaunchedEffect(live) {
        while (live) {
            delay(15_000)
            vm.refreshLive()
        }
    }
}

// ----------------------------------------------------------------------------- war

@Composable
private fun WarPage(vm: ClanViewModel, s: ClanViewModel.UiState, push: (ClanPage) -> Unit) {
    val war = s.home?.war ?: return
    WarCard(war)
    val rally = war.rally
    if (war.isLive && rally != null) {
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { RallyButton(rally.available, war.gap < 0, vm::rally) }
    }
    if (war.rivals.isNotEmpty()) {
        Card {
            TokenText(stringResource(if (war.isLobby) R.string.clanwar_in_this_war else R.string.clanwar_standings), TypographyTokens.LabelDisplay,
                color = ColorTokens.TextSecondary.resolve())
            WarStandings(war) { push(ClanPage.Profile(it)) }
        }
    }
    if (!war.isLobby) LinkRow("👥", stringResource(R.string.clanwar_who_pushed_link)) { push(ClanPage.Fighters(war.id, null)) }
    if (war.isLive) SideViewNotice(compact = true)
    if (war.feed.isNotEmpty()) Card { WarFeed(war.feed) }
    Card {
        TokenText(stringResource(R.string.clanwar_how), TypographyTokens.LabelDisplay, color = ColorTokens.TextSecondary.resolve())
        listOf(R.string.clanwar_rule_groups, R.string.clanwar_rule_time, R.string.clanwar_rule_points, R.string.clanwar_rule_trophies,
            R.string.clanwar_rule_sunday).forEach {
            TokenText("• " + stringResource(it), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
        }
    }
}

@Composable
private fun LinkRow(glyph: String, text: String, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = MinTouchTarget).clip(RoundedCornerShape(RadiusTokens.M))
            .background(ColorTokens.BgSurface.resolve()).clickable(role = Role.Button, onClick = onClick).padding(SpacingTokens.M),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Sm),
    ) {
        TokenText(glyph, TypographyTokens.TitleS, Modifier.clearAndSetSemantics {})
        TokenText(text, TypographyTokens.TitleS, Modifier.weight(1f))
        TokenText("›", TypographyTokens.TitleM, color = ColorTokens.TextTertiary.resolve())
    }
}

/** All clans of a live war, one lane each — the emblem runs toward the leader's mark as push-ups land. */
@Composable
internal fun WarArena(war: ClanWar) {
    val top = maxOf(war.clans.maxOfOrNull { it.score } ?: 0, 1)
    Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.Sm)) {
        war.clans.forEach { s -> key(s.clan.id) { WarLane(s, top, leader = s.rank == 1 && s.score > 0) } }
    }
}

@Composable
private fun WarLane(s: ClanWar.Standing, top: Int, leader: Boolean) {
    val color = badgeColor(s.clan).resolve()
    val frac by animateFloatAsState(s.score.toFloat() / top, spring(dampingRatio = 0.78f, stiffness = 120f), label = "lane")
    val shown by animateIntAsState(s.score, tween(900), label = "score")
    var gain by remember { mutableStateOf<Int?>(null) }
    var prev by remember { mutableStateOf(s.score) }
    var shownGain by remember { mutableStateOf(0) }
    val pop by animateFloatAsState(if (gain != null) 1f else 0f, tween(if (gain != null) 250 else 400), label = "pop")
    LaunchedEffect(s.score) {
        if (s.score > prev) {
            gain = s.score - prev
            shownGain = s.score - prev
            prev = s.score
            delay(2200)
            gain = null
        } else {
            prev = s.score
        }
    }
    val a11y = stringResource(R.string.clanwar_lane_a11y, s.clan.name, s.rank ?: 0, s.score)
    Column(Modifier.clearAndSetSemantics { contentDescription = a11y }, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
            TokenText(rankMedal(s.rank), TypographyTokens.BodyS)
            TokenText(s.clan.name, TypographyTokens.LabelDisplay, maxLines = 1,
                color = (if (s.isMine) ColorTokens.BrandFlameText else ColorTokens.TextSecondary).resolve())
            if (s.isMine) TokenText(stringResource(R.string.clanwar_you), TypographyTokens.Overline, color = ColorTokens.BrandFlameText.resolve())
            Spacer(Modifier.weight(1f))
            TokenText("$shown", TypographyTokens.TitleM, color = (if (leader) ColorTokens.LeagueGold else ColorTokens.TextPrimary).resolve())
        }
        BoxWithConstraints(Modifier.fillMaxWidth().height(38.dp)) {
            val marker = 34.dp
            val x = (maxWidth - marker) * frac
            Box(Modifier.align(Alignment.CenterStart).fillMaxWidth().height(12.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.06f)))
            Box(
                Modifier.align(Alignment.CenterStart).width(x + marker / 2).height(12.dp).clip(CircleShape)
                    .background(Brush.horizontalGradient(listOf(color.copy(alpha = 0.15f), color.copy(alpha = 0.9f)))),
            )
            Box(Modifier.align(Alignment.CenterStart).offset(x = x)) {
                ClanEmblem(s.clan.badge, s.clan.tag, marker)
                if (leader) TokenText("👑", TypographyTokens.Caption, Modifier.align(Alignment.TopCenter).offset(y = (-12).dp))
            }
            if (shownGain > 0) {
                TokenText(
                    "+$shownGain", TypographyTokens.TitleS,
                    Modifier.align(Alignment.CenterStart).offset(x = minOf(x + marker + 4.dp, maxWidth - 44.dp))
                        .graphicsLayer { alpha = pop; scaleX = 0.4f + 0.6f * pop; scaleY = 0.4f + 0.6f * pop },
                    color = ColorTokens.StateSuccessText.resolve(),
                )
            }
        }
    }
}

/** The newest feed line, sliding in when someone scores. */
@Composable
internal fun WarTicker(feed: List<ClanWar.FeedItem>) {
    val first = feed.firstOrNull() ?: return
    AnimatedContent(
        targetState = first,
        transitionSpec = { slideInVertically { it } + fadeIn() togetherWith slideOutVertically { -it } + fadeOut() },
        label = "ticker",
    ) { f ->
        Row(
            Modifier.fillMaxWidth().clip(CircleShape).background(Color.Black.copy(alpha = 0.3f))
                .padding(horizontal = SpacingTokens.Sm, vertical = SpacingTokens.Xs).semantics(mergeDescendants = true) {},
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Xs),
        ) {
            TokenText(if (f.mine) "🔥" else "⚔️", TypographyTokens.BodyS, Modifier.clearAndSetSemantics {})
            TokenText(f.username, TypographyTokens.BodyS, maxLines = 1)
            TokenText("+${f.points}", TypographyTokens.TitleS, color = (if (f.mine) ColorTokens.StateSuccessText else ColorTokens.StateDanger).resolve())
            TokenText(stringResource(R.string.clanwar_for_clan, f.clanName), TypographyTokens.Caption, Modifier.weight(1f), maxLines = 1,
                color = ColorTokens.TextTertiary.resolve())
            agoText(f.at)?.let { TokenText(it, TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve()) }
        }
    }
}

@Composable
private fun agoText(iso: String): String? {
    val m = WarDates.minutesAgo(iso) ?: return null
    return when {
        m < 1 -> stringResource(R.string.clanwar_ago_now)
        m < 60 -> stringResource(R.string.clanwar_ago_min, m)
        m < 1440 -> stringResource(R.string.clanwar_ago_h, m / 60)
        else -> stringResource(R.string.clanwar_ago_d, m / 1440)
    }
}

// ----------------------------------------------------------------------------- history

private fun placeColor(rank: Int, of: Int): TokenColor = when {
    rank == 1 && of > 1 -> ColorTokens.LeagueGold
    rank == of -> ColorTokens.StateDanger
    else -> ColorTokens.TextSecondary
}

@Composable
private fun HistoryPage(vm: ClanViewModel, s: ClanViewModel.UiState, push: (ClanPage) -> Unit) {
    LaunchedEffect(Unit) { vm.loadWarExtras() }
    WarRecordCard(WarRecord.of(s.warHistory))
    if (s.warHistory.isEmpty()) {
        Column(Modifier.fillMaxWidth().padding(vertical = SpacingTokens.Xl), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
            TokenText("🏰", TypographyTokens.DisplayL, Modifier.clearAndSetSemantics {})
            TokenText(stringResource(R.string.clanwar_none_title), TypographyTokens.TitleM)
            TokenText(stringResource(R.string.clanwar_none_body), TypographyTokens.Caption, color = ColorTokens.TextSecondary.resolve(),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        }
    } else {
        SectionLabel(stringResource(R.string.clanwar_last_wars))
        s.warHistory.forEach { w -> WarResultCard(w) { push(ClanPage.Fighters(w.id, null)) } }
    }
}

@Composable
internal fun WarRecordCard(r: WarRecord) {
    val shape = RoundedCornerShape(RadiusTokens.L)
    val track = Color.White.copy(alpha = 0.08f)
    val ring = ColorTokens.StateSuccess.resolve()
    Column(
        Modifier.fillMaxWidth().clip(shape)
            .background(Brush.linearGradient(listOf(ColorTokens.BrandVolt.resolve().copy(alpha = 0.18f), ColorTokens.BgSurface.resolve())))
            .border(1.dp, ColorTokens.StrokeSubtle.resolve(), shape).padding(SpacingTokens.Ml).semantics(mergeDescendants = true) {},
        verticalArrangement = Arrangement.spacedBy(SpacingTokens.M),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.L)) {
            Box(Modifier.size(96.dp), contentAlignment = Alignment.Center) {
                Canvas(Modifier.size(96.dp)) {
                    val stroke = Stroke(width = 10.dp.toPx(), cap = StrokeCap.Round)
                    drawArc(track, 0f, 360f, false, style = stroke)
                    drawArc(ring, -90f, (360 * r.winRate).toFloat(), false, style = stroke)
                }
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    TokenText(if (r.played == 0) "–" else "${Math.round(r.winRate * 100)}%", TypographyTokens.TitleL)
                    TokenText(stringResource(R.string.clanwar_wars_won), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
                    Tally(r.wins, stringResource(R.string.clanwar_won), ColorTokens.LeagueGold)
                    Tally(r.played, stringResource(R.string.clanwar_wars), ColorTokens.TextPrimary)
                }
                if (r.form.isNotEmpty()) {
                    TokenText(stringResource(R.string.clanwar_last_places, r.form.size), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        r.form.asReversed().forEach { rank ->
                            Box(
                                Modifier.size(16.dp).clip(RoundedCornerShape(3.dp))
                                    .background((if (rank == 1) ColorTokens.LeagueGold else ColorTokens.BgElevated).resolve()),
                                contentAlignment = Alignment.Center,
                            ) {
                                TokenText("$rank", TypographyTokens.Overline,
                                    color = if (rank == 1) Color.Black.copy(alpha = 0.7f) else ColorTokens.TextSecondary.resolve())
                            }
                        }
                    }
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
            if (r.trophyNet != 0) {
                Pill(stringResource(R.string.clanwar_trophies_net, if (r.trophyNet > 0) "+${r.trophyNet}" else "${r.trophyNet}"),
                    color = if (r.trophyNet > 0) ColorTokens.LeagueGold else ColorTokens.StateDanger)
            }
            if (r.bestStreak > 1) Pill(stringResource(R.string.clanwar_best_streak, r.bestStreak), color = ColorTokens.BrandFlameText)
        }
    }
}

@Composable
private fun Tally(n: Int, label: String, color: TokenColor) {
    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
        TokenText("$n", TypographyTokens.Stat, color = color.resolve())
        TokenText(label, TypographyTokens.Caption, Modifier.padding(bottom = 4.dp), color = ColorTokens.TextTertiary.resolve())
    }
}

@Composable
private fun WarResultCard(war: ClanWarResult, onClick: () -> Unit) {
    val won = war.letter == "W"
    val tint = placeColor(war.rank, war.of).resolve()
    val shape = RoundedCornerShape(RadiusTokens.L)
    val top = maxOf(war.clans.maxOfOrNull { it.score } ?: 0, 1)
    val title = stringResource(
        when {
            won -> R.string.clanwar_title_victory
            war.rank == war.of -> R.string.clanwar_title_last
            war.rank == 2 -> R.string.clanwar_title_second
            else -> R.string.clanwar_title_third
        },
    )
    Column(
        Modifier.fillMaxWidth().clip(shape)
            .background(Brush.linearGradient(listOf(tint.copy(alpha = if (won) 0.16f else 0.08f), ColorTokens.BgSurface.resolve())))
            .border(1.dp, tint.copy(alpha = if (won) 0.5f else 0.2f), shape)
            .clickable(role = Role.Button, onClick = onClick).padding(SpacingTokens.M).semantics(mergeDescendants = true) {},
        verticalArrangement = Arrangement.spacedBy(SpacingTokens.Sm),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
            TokenText(title, TypographyTokens.TitleM, color = tint)
            TokenText(stringResource(R.string.clanwar_of, war.of), TypographyTokens.Caption, Modifier.weight(1f), color = ColorTokens.TextTertiary.resolve())
            TokenText(if (war.ratingDelta >= 0) "+${war.ratingDelta} 🏆" else "${war.ratingDelta} 🏆", TypographyTokens.TitleS,
                color = (if (war.ratingDelta >= 0) ColorTokens.LeagueGold else ColorTokens.StateDanger).resolve())
        }
        TokenText(WarDates.week(war.weekStart), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
        war.clans.forEach { c ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Sm)) {
                TokenText(rankMedal(c.rank), TypographyTokens.BodyS, Modifier.width(28.dp))
                ClanEmblem(c.badge, c.tag, 28.dp)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Row {
                        TokenText(c.name, TypographyTokens.BodyS, Modifier.weight(1f), maxLines = 1,
                            color = (if (c.isMine) ColorTokens.BrandFlameText else ColorTokens.TextPrimary).resolve())
                        TokenText("${c.score}", TypographyTokens.BodyS)
                    }
                    Box(
                        Modifier.fillMaxWidth(maxOf(0.03f, c.score.toFloat() / top)).height(5.dp).clip(CircleShape)
                            .background(if (c.isMine) ColorTokens.BrandFlame.resolve() else ColorTokens.TextTertiary.resolve().copy(alpha = 0.5f)),
                    )
                }
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
            war.mvp?.let {
                Avatar(it.username, it.avatarPreset, size = 26.dp, frame = it.frame)
                TokenText(stringResource(R.string.clanwar_mvp, it.username), TypographyTokens.Caption, maxLines = 1, color = ColorTokens.TextSecondary.resolve())
            }
            war.contributors?.let {
                TokenText(stringResource(R.string.clanwar_fighters_n, it), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
            }
            Spacer(Modifier.weight(1f))
            TokenText(stringResource(R.string.clanwar_who_pushed), TypographyTokens.Caption, color = ColorTokens.BrandFlameText.resolve())
            TokenText("›", TypographyTokens.TitleS, color = ColorTokens.TextTertiary.resolve())
        }
    }
}

// ----------------------------------------------------------------------------- who pushed

@Composable
private fun FightersPage(vm: ClanViewModel, page: ClanPage.Fighters, push: (ClanPage) -> Unit) {
    var detail by remember { mutableStateOf<ClanWarDetail?>(null) }
    var failed by remember { mutableStateOf(false) }
    var selected by remember { mutableStateOf(page.clanId) }
    val scope = rememberCoroutineScope()
    val load: () -> Unit = {
        scope.launch {
            val d = vm.warDetail(page.warId)
            failed = d == null
            if (d != null) {
                detail = d
                if (selected == null) selected = d.mySide?.clanId
            }
        }
    }
    LaunchedEffect(page.warId) { load() }
    val d = detail
    if (d == null) {
        if (failed) {
            InlineBanner(stringResource(R.string.clanwar_load_failed), BannerKind.Warning)
        } else {
            Box(Modifier.fillMaxWidth().height(200.dp), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = ColorTokens.BrandFlame.resolve())
            }
        }
        return
    }
    val side = d.side(selected) ?: d.mySide
    val standing = d.war.clans.firstOrNull { it.clan.id == side?.clanId }
    TokenText(WarDates.week(d.war.weekStart), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
        d.war.clans.forEach { s ->
            val on = s.clan.id == side?.clanId
            Row(
                Modifier.heightIn(min = MinTouchTarget).clip(CircleShape)
                    .background((if (on) ColorTokens.BgElevated else ColorTokens.BgSurface).resolve())
                    .border(if (on) 2.dp else 1.dp, if (on) badgeColor(s.clan).resolve() else ColorTokens.StrokeSubtle.resolve(), CircleShape)
                    .clickable(role = Role.Tab) { selected = s.clan.id }.padding(horizontal = SpacingTokens.Sm),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Xs),
            ) {
                TokenText(rankMedal(s.rank), TypographyTokens.BodyS)
                ClanEmblem(s.clan.badge, s.clan.tag, 26.dp)
                Column {
                    TokenText(s.clan.name, TypographyTokens.Caption, maxLines = 1,
                        color = (if (s.isMine) ColorTokens.BrandFlameText else ColorTokens.TextPrimary).resolve())
                    TokenText("${s.score}", TypographyTokens.LabelDisplay, color = ColorTokens.TextSecondary.resolve())
                }
            }
        }
    }
    if (side == null || standing == null) return
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(RadiusTokens.L)).background(ColorTokens.BgSurface.resolve()).padding(SpacingTokens.M),
        verticalArrangement = Arrangement.spacedBy(SpacingTokens.Sm),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
            ClanEmblem(standing.clan.badge, standing.clan.tag, 52.dp)
            Column(Modifier.weight(1f)) {
                TokenText(standing.clan.name, TypographyTokens.TitleM)
                TokenText(stringResource(R.string.clanwar_fought, side.active, side.fighters.size, standing.score), TypographyTokens.Caption,
                    color = ColorTokens.TextSecondary.resolve())
            }
            val about = stringResource(R.string.clanwar_about, standing.clan.name)
            Box(
                Modifier.size(MinTouchTarget).clip(CircleShape).clickable(role = Role.Button) { push(ClanPage.Profile(standing.clan.id)) }
                    .semantics { contentDescription = about },
                contentAlignment = Alignment.Center,
            ) { TokenText("ⓘ", TypographyTokens.TitleM, Modifier.clearAndSetSemantics {}, color = ColorTokens.TextSecondary.resolve()) }
        }
        if (side.idle.isNotEmpty()) {
            TokenText("⚠️ " + stringResource(R.string.clanwar_idle, side.idle.size), TypographyTokens.Caption, color = ColorTokens.StateWarning.resolve())
        }
    }
    Row(Modifier.fillMaxWidth().padding(horizontal = SpacingTokens.Sm).clearAndSetSemantics {}, verticalAlignment = Alignment.CenterVertically) {
        Spacer(Modifier.weight(1f))
        Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            WarDates.dayLetters.forEach { TokenText(it, TypographyTokens.Overline, Modifier.width(9.dp), color = ColorTokens.TextTertiary.resolve()) }
        }
        TokenText(stringResource(R.string.clanwar_points), TypographyTokens.Caption, Modifier.width(56.dp),
            color = ColorTokens.TextTertiary.resolve(), textAlign = androidx.compose.ui.text.style.TextAlign.End)
    }
    side.fighters.forEachIndexed { i, f -> FighterRow(i + 1, f, maxOf(side.bestDay, 1)) }
    if (side.fighters.isEmpty()) {
        TokenText(stringResource(R.string.clanwar_nobody), TypographyTokens.BodyS, color = ColorTokens.TextTertiary.resolve())
    }
    TokenText(stringResource(R.string.clanwar_points_rule), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
}

@Composable
private fun FighterRow(place: Int, f: ClanWarDetail.Fighter, scale: Int) {
    val idle = f.points == 0
    val a11y = if (idle) stringResource(R.string.clanwar_fighter_idle_a11y, f.user.username)
    else stringResource(R.string.clanwar_fighter_a11y, f.user.username, f.points, f.raw)
    val hero = Brush.verticalGradient(listOf(ColorTokens.BrandFlame.resolve(), ColorTokens.BrandVolt.resolve()))
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(RadiusTokens.M)).background(ColorTokens.BgSurface.resolve())
            .profileLink(ProfileTarget.User(f.user.id)).padding(SpacingTokens.Sm).clearAndSetSemantics { contentDescription = a11y },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Sm),
    ) {
        TokenText(if (place <= 3 && !idle) listOf("🥇", "🥈", "🥉")[place - 1] else "$place", TypographyTokens.Caption, Modifier.width(24.dp),
            color = ColorTokens.TextTertiary.resolve())
        Avatar(f.user.username, f.user.avatarPreset, size = 36.dp, frame = f.user.frame)
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
                TokenText(f.user.username, TypographyTokens.TitleS, Modifier.weight(1f, fill = false), maxLines = 1)
                if (!f.inClan) Pill(stringResource(R.string.clanwar_left), color = ColorTokens.TextTertiary)
            }
            TokenText(
                if (idle) stringResource(R.string.clanwar_didnt_fight) else stringResource(R.string.clanwar_pushups, f.raw),
                TypographyTokens.Caption, color = (if (idle) ColorTokens.StateDanger else ColorTokens.TextTertiary).resolve(),
            )
        }
        Row(Modifier.height(26.dp), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            f.days.forEach { v ->
                Box(
                    Modifier.width(9.dp).height(maxOf(3f, 26f * v / scale).dp).clip(RoundedCornerShape(2.dp))
                        .then(if (v > 0) Modifier.background(hero) else Modifier.background(Color.White.copy(alpha = 0.08f))),
                )
            }
        }
        TokenText("${f.points}", TypographyTokens.TitleM, Modifier.width(56.dp),
            color = (if (idle) ColorTokens.StateDanger else ColorTokens.TextPrimary).resolve(), textAlign = androidx.compose.ui.text.style.TextAlign.End)
    }
}

// ----------------------------------------------------------------------------- clan page

/** Any clan's page full screen with a back button (D-080: opened from a profile, the leaderboard…). */
@Composable
fun ClanPageScreen(vm: ClanViewModel, clanId: String, onBack: () -> Unit, modifier: Modifier = Modifier) {
    Box(modifier.fillMaxSize()) {
        ClanBackdrop(ColorTokens.BrandCyan)
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = SpacingTokens.M, vertical = SpacingTokens.S),
            verticalArrangement = Arrangement.spacedBy(SpacingTokens.M),
        ) {
            val back = stringResource(R.string.clan_back)
            Box(
                Modifier.heightIn(min = MinTouchTarget).clip(CircleShape).clickable(role = Role.Button, onClick = onBack)
                    .padding(horizontal = SpacingTokens.S),
                contentAlignment = Alignment.CenterStart,
            ) { TokenText(back, TypographyTokens.TitleS, color = ColorTokens.BrandFlameText.resolve()) }
            ClanProfilePage(vm, clanId)
            Spacer(Modifier.height(SpacingTokens.Xl))
        }
    }
}

@Composable
private fun ClanProfilePage(vm: ClanViewModel, clanId: String) {
    var home by remember { mutableStateOf<ClanHome?>(null) }
    var results by remember { mutableStateOf<List<ClanWarResult>>(emptyList()) }
    var failed by remember { mutableStateOf(false) }
    LaunchedEffect(clanId) {
        val h = vm.clanProfile(clanId)
        failed = h == null
        home = h
        results = vm.clanResults(clanId)
    }
    val h = home
    if (h == null) {
        if (failed) {
            InlineBanner(stringResource(R.string.clan_profile_failed), BannerKind.Warning)
        } else {
            Box(Modifier.fillMaxWidth().height(240.dp), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = ColorTokens.BrandFlame.resolve())
            }
        }
        return
    }
    val s = h.summary
    val record = WarRecord.of(results)
    Column(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}, horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
        ClanEmblem(s.badge, s.tag, 112.dp)
        TokenText(s.name, TypographyTokens.DisplayM, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        if (s.myRole != null) Pill(stringResource(R.string.clan_profile_your), color = ColorTokens.BrandFlameText)
        if (s.description.isNotBlank()) {
            TokenText(s.description, TypographyTokens.BodyS, color = ColorTokens.TextSecondary.resolve(),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        }
    }
    Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
        ProfileStat("🛡️", "${s.rating}", stringResource(R.string.clan_profile_trophies), ColorTokens.LeagueGold, Modifier.weight(1f))
        ProfileStat("👥", "${s.memberCount}/${s.maxMembers}", stringResource(R.string.clan_members), ColorTokens.BrandCyan, Modifier.weight(1f))
        ProfileStat("⚔️", if (record.played == 0) "–" else "${record.wins}/${record.played}", stringResource(R.string.clan_profile_wars_won),
            ColorTokens.StateSuccessText, Modifier.weight(1f))
    }
    Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
        Pill(stringResource(when (s.joinPolicy) {
            "open" -> R.string.clan_policy_open
            "request" -> R.string.clan_policy_request
            else -> R.string.clan_policy_invite
        }), color = ColorTokens.TextSecondary)
        if (s.minTrophies > 0) Pill(stringResource(R.string.clan_profile_min, s.minTrophies), color = ColorTokens.TextSecondary)
        h.war?.let { Pill(stringResource(if (it.isLive) R.string.clan_profile_in_war else R.string.clan_profile_in_lobby),
            color = if (it.isLive) ColorTokens.StateDanger else ColorTokens.TextSecondary) }
    }
    if (record.form.isNotEmpty()) WarRecordCard(record)
    SectionLabel(stringResource(R.string.clan_profile_members_header, s.memberCount, s.maxMembers))
    h.members.sortedWith(compareByDescending<ClanHome.Member> { ClanRole.of(it.role)?.rank ?: 0 }.thenByDescending { it.user.trophies ?: 0 })
        .forEach { m -> ProfileMemberRow(m) }
}

@Composable
private fun ProfileStat(glyph: String, value: String, label: String, tint: TokenColor, modifier: Modifier) {
    Column(
        modifier.clip(RoundedCornerShape(RadiusTokens.M)).background(ColorTokens.BgSurface.resolve().copy(alpha = 0.92f))
            .padding(vertical = SpacingTokens.Sm).semantics(mergeDescendants = true) {},
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        TokenText(glyph, TypographyTokens.BodyS, Modifier.clearAndSetSemantics {})
        TokenText(value, TypographyTokens.TitleM, color = tint.resolve(), maxLines = 1)
        TokenText(label, TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve(), maxLines = 1)
    }
}

@Composable
private fun ProfileMemberRow(m: ClanHome.Member) {
    val role = ClanRole.of(m.role) ?: ClanRole.Member
    Row(
        Modifier.fillMaxWidth().heightIn(min = MinTouchTarget).clip(RoundedCornerShape(RadiusTokens.M))
            .background(ColorTokens.BgSurface.resolve().copy(alpha = 0.92f)).profileLink(ProfileTarget.User(m.user.id))
            .padding(SpacingTokens.Sm).semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Sm),
    ) {
        Avatar(m.user.username, m.user.avatarPreset, size = 40.dp, frame = m.user.frame)
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
                TokenText(m.user.username, TypographyTokens.TitleS, Modifier.weight(1f, fill = false), maxLines = 1)
                if (m.user.pro == true) ProBadge()
            }
            val level = m.user.level?.let { " · " + stringResource(R.string.clan_profile_level, it) } ?: ""
            TokenText(roleLabel(role) + level, TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
        }
        Column(horizontalAlignment = Alignment.End) {
            TokenText("🏆 ${m.user.trophies ?: 0}", TypographyTokens.BodyS, color = ColorTokens.LeagueGold.resolve())
            TokenText(stringResource(R.string.clan_profile_this_war, m.warReps), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
        }
    }
}
