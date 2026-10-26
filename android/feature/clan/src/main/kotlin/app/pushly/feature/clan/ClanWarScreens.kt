package app.pushly.feature.clan

import android.content.Context
import androidx.compose.animation.core.animateIntAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import app.pushly.core.designsystem.Avatar
import app.pushly.core.designsystem.ClanEmblem
import app.pushly.core.designsystem.MinTouchTarget
import app.pushly.core.designsystem.Pill
import app.pushly.core.designsystem.PrimaryButton
import app.pushly.core.designsystem.SecondaryButton
import app.pushly.core.designsystem.SectionLabel
import app.pushly.core.designsystem.SideViewNotice
import app.pushly.core.designsystem.TokenText
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.RadiusTokens
import app.pushly.core.designsystem.generated.SpacingTokens
import app.pushly.core.designsystem.generated.TypographyTokens
import app.pushly.core.designsystem.resolve

// Clan Wars v2 (D-078): lobby → live → Sunday results, groups of 2–4 clans. Same as iOS ClanWarViews.

/** Which results the player has already seen (the result screen shows once per war, on this device). */
internal object WarResultSeen {
    private const val PREFS = "clan_war"
    private const val KEY = "seen_results"

    fun contains(context: Context, id: String): Boolean =
        id in context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, "").orEmpty().split(',')

    fun mark(context: Context, id: String) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val seen = prefs.getString(KEY, "").orEmpty().split(',').filter { it.isNotBlank() && it != id }.takeLast(29) + id
        prefs.edit().putString(KEY, seen.joinToString(",")).apply()
    }
}

internal fun rankMedal(rank: Int?): String = when (rank) {
    1 -> "🥇"
    2 -> "🥈"
    3 -> "🥉"
    null -> "–"
    else -> "#$rank"
}

@Composable
private fun clock(iso: String): String? {
    val (d, h, m) = WarClock.until(iso) ?: return null
    return when {
        d > 0 -> stringResource(R.string.clanwar_clock_days, d, h)
        h > 0 -> stringResource(R.string.clanwar_clock_hours, h, m)
        else -> stringResource(R.string.clanwar_clock_minutes, maxOf(m, 1))
    }
}

/** The war on the clan lobby: who we fight, the clock, and (live) the standings. */
@Composable
internal fun WarCard(war: ClanWar) {
    val shape = RoundedCornerShape(RadiusTokens.L)
    val border = if (war.isLive) ColorTokens.StateDanger.resolve().copy(alpha = 0.55f) else ColorTokens.StrokeSubtle.resolve()
    Column(
        Modifier.fillMaxWidth().clip(shape).background(ColorTokens.BgSurface.resolve().copy(alpha = 0.9f))
            .border(if (war.isLive) 1.5.dp else 1.dp, border, shape).padding(SpacingTokens.M)
            .semantics(mergeDescendants = true) {},
        verticalArrangement = Arrangement.spacedBy(SpacingTokens.Sm),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
            TokenText(stringResource(if (war.isLobby) R.string.clanwar_next else R.string.clan_war_title), TypographyTokens.Overline,
                color = ColorTokens.TextSecondary.resolve())
            if (war.isLive) {
                TokenText(stringResource(R.string.clan_war_live_tag), TypographyTokens.Overline,
                    Modifier.clip(CircleShape).background(ColorTokens.StateDanger.resolve()).padding(horizontal = 6.dp, vertical = 1.dp),
                    color = Color.White)
            }
            Spacer(Modifier.weight(1f))
            clock(if (war.isLobby) war.startsAt else war.endsAt)?.let { left ->
                TokenText(stringResource(if (war.isLobby) R.string.clanwar_starts_in else R.string.clanwar_ends_in, left),
                    TypographyTokens.Caption, color = ColorTokens.BrandFlameText.resolve(), maxLines = 1)
            }
        }
        if (war.isLobby) LobbyBody(war) else LiveBody(war)
        Row(verticalAlignment = Alignment.CenterVertically) {
            val gap = war.gap
            val line = when {
                war.isLobby && war.rivals.isEmpty() -> stringResource(R.string.clanwar_waiting)
                war.isLobby -> stringResource(R.string.clanwar_clans_monday, war.clans.size)
                gap > 0 -> stringResource(R.string.clanwar_first_ahead, gap)
                gap == 0 || war.myRank == 1 -> stringResource(R.string.clanwar_tied)
                else -> stringResource(R.string.clanwar_behind_leader, war.myRank ?: 0, -gap)
            }
            val color = when {
                war.isLobby -> ColorTokens.TextPrimary
                gap > 0 -> ColorTokens.StateSuccessText
                gap < 0 -> ColorTokens.StateDanger
                else -> ColorTokens.TextPrimary
            }
            TokenText(line, TypographyTokens.TitleS, Modifier.weight(1f), color = color.resolve(), maxLines = 1)
            val stakes = war.mine?.stakes
            if (stakes != null && war.rivals.isNotEmpty()) {
                TokenText("+${stakes.win} / ${stakes.last} 🏆", TypographyTokens.Caption, color = ColorTokens.LeagueGold.resolve(),
                    modifier = Modifier.clip(CircleShape).background(ColorTokens.LeagueGold.resolve().copy(alpha = 0.14f))
                        .padding(horizontal = 8.dp, vertical = 3.dp))
            }
            TokenText(" ›", TypographyTokens.TitleM, color = ColorTokens.TextTertiary.resolve())
        }
    }
}

@Composable
private fun LobbyBody(war: ClanWar) {
    if (war.rivals.isEmpty()) {
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
            war.mine?.let { ClanEmblem(it.clan.badge, it.clan.tag, 84.dp) }
            TokenText(stringResource(R.string.clanwar_looking), TypographyTokens.TitleM)
            TokenText(stringResource(if (war.movedWeeks > 0) R.string.clanwar_looking_moved else R.string.clanwar_looking_body),
                TypographyTokens.Caption, color = ColorTokens.TextSecondary.resolve(), textAlign = TextAlign.Center)
        }
    } else {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
            war.clans.forEachIndexed { i, s ->
                if (i > 0) TokenText("VS", TypographyTokens.TitleS, Modifier.padding(top = 20.dp), color = ColorTokens.TextTertiary.resolve())
                Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    ClanEmblem(s.clan.badge, s.clan.tag, if (war.clans.size > 3) 46.dp else 58.dp)
                    TokenText(s.clan.name, TypographyTokens.Caption, maxLines = 1,
                        color = (if (s.isMine) ColorTokens.BrandFlameText else ColorTokens.TextPrimary).resolve())
                    TokenText("🏆 ${s.clan.rating}", TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
                }
            }
        }
    }
}

@Composable
private fun LiveBody(war: ClanWar) {
    val me = war.mine
    val them = war.rivals.firstOrNull()
    if (war.clans.size == 2 && me != null && them != null) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
            DuelSide(me, Modifier.weight(1f))
            TokenText("VS", TypographyTokens.DisplayM)
            DuelSide(them, Modifier.weight(1f))
        }
        val us by animateIntAsState(me.score, tween(700), label = "us")
        val they by animateIntAsState(them.score, tween(700), label = "them")
        TugBar(us, they, badgeColor(me.clan).resolve(), badgeColor(them.clan).resolve())
    } else {
        WarArena(war)
    }
    if (war.feed.isNotEmpty()) WarTicker(war.feed)
}

@Composable
private fun DuelSide(s: ClanWar.Standing, modifier: Modifier) {
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
        TokenText(if (s.rank == 1 && s.score > 0) "👑" else " ", TypographyTokens.TitleM, Modifier.clearAndSetSemantics {})
        ClanEmblem(s.clan.badge, s.clan.tag, 60.dp)
        TokenText(s.clan.name, TypographyTokens.LabelDisplay, maxLines = 1,
            color = (if (s.isMine) ColorTokens.BrandFlameText else ColorTokens.TextSecondary).resolve())
        val shown by animateIntAsState(s.score, tween(900), label = "score")
        TokenText("$shown", TypographyTokens.DisplayM, maxLines = 1)
    }
}

/** Standings rows: medal, emblem, name, score bar, clan trophies (finished) or stakes. */
@Composable
internal fun WarStandings(war: ClanWar, compact: Boolean = false, onClan: ((String) -> Unit)? = null) {
    val top = maxOf(war.clans.maxOfOrNull { it.score } ?: 0, 1)
    Column(verticalArrangement = Arrangement.spacedBy(if (compact) SpacingTokens.Xs else SpacingTokens.S)) {
        war.clans.forEach { s ->
            Row(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(RadiusTokens.M))
                    .background(if (s.isMine && !compact) ColorTokens.BrandFlame.resolve().copy(alpha = 0.10f) else Color.Transparent)
                    .then(if (onClan != null) Modifier.clickable(role = Role.Button) { onClan(s.clan.id) } else Modifier)
                    .padding(if (compact) 0.dp else SpacingTokens.S).semantics(mergeDescendants = true) {},
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Sm),
            ) {
                TokenText(rankMedal(s.rank), TypographyTokens.TitleM, Modifier.width(34.dp), textAlign = TextAlign.Center)
                ClanEmblem(s.clan.badge, s.clan.tag, if (compact) 30.dp else 38.dp)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Row {
                        TokenText(s.clan.name, TypographyTokens.TitleS, Modifier.weight(1f), maxLines = 1,
                            color = (if (s.isMine) ColorTokens.BrandFlameText else ColorTokens.TextPrimary).resolve())
                        TokenText("${s.score}", TypographyTokens.TitleS)
                    }
                    Box(Modifier.fillMaxWidth().height(6.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.07f))) {
                        Box(Modifier.fillMaxWidth(maxOf(0.03f, s.score.toFloat() / top)).height(6.dp).clip(CircleShape)
                            .background(badgeColor(s.clan).resolve()))
                    }
                    if (!compact) {
                        Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                            val d = s.ratingDelta
                            val st = s.stakes
                            if (d != null) {
                                TokenText(if (d >= 0) "+$d 🏆" else "$d 🏆", TypographyTokens.Caption,
                                    color = (if (d >= 0) ColorTokens.LeagueGold else ColorTokens.StateDanger).resolve())
                            } else if (st != null) {
                                TokenText(stringResource(R.string.clanwar_stakes_line, st.win, st.last), TypographyTokens.Caption,
                                    color = ColorTokens.TextTertiary.resolve())
                            }
                            s.mvp?.let {
                                TokenText(stringResource(R.string.clanwar_mvp, it.username), TypographyTokens.Caption, color = ColorTokens.TextSecondary.resolve())
                            }
                        }
                    }
                }
                if (onClan != null) TokenText("›", TypographyTokens.TitleM, color = ColorTokens.TextTertiary.resolve())
            }
        }
    }
}

/** Sunday results (D-078): shown first when the player opens the tab after a war, then the next lobby. */
@Composable
internal fun WarResultDialog(war: ClanWar, onContinue: () -> Unit, onOpen: (ClanPage) -> Unit) {
    val r = war.result
    val won = r != null && r.rank == 1 && r.of > 1
    val delta = r?.ratingDelta ?: 0
    Dialog(onDismissRequest = onContinue, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Box(Modifier.fillMaxSize()) {
            ClanBackdrop(if (won) ColorTokens.LeagueGold else war.mine?.let { badgeColor(it.clan) } ?: ColorTokens.BrandCyan)
            Column(
                Modifier.fillMaxSize().safeDrawingPadding().verticalScroll(rememberScrollState())
                    .padding(horizontal = SpacingTokens.Gutter, vertical = SpacingTokens.Xl),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(SpacingTokens.L),
            ) {
                TokenText(stringResource(R.string.clanwar_results), TypographyTokens.Overline, color = ColorTokens.TextSecondary.resolve())
                war.mine?.let {
                    Box(Modifier.shadow(24.dp, CircleShape, ambientColor = ColorTokens.LeagueGold.resolve(), spotColor = ColorTokens.LeagueGold.resolve())) {
                        ClanEmblem(it.clan.badge, it.clan.tag, 120.dp)
                    }
                }
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
                    TokenText(
                        if (won) stringResource(R.string.clanwar_victory)
                        else stringResource(R.string.clanwar_place_of, r?.rank ?: 0, r?.of ?: 0),
                        TypographyTokens.DisplayL, color = (if (won) ColorTokens.LeagueGold else ColorTokens.TextPrimary).resolve(),
                    )
                    TokenText(stringResource(R.string.clanwar_trophies_delta, if (delta >= 0) "+$delta" else "$delta"), TypographyTokens.TitleM,
                        color = (if (delta >= 0) ColorTokens.StateSuccessText else ColorTokens.StateDanger).resolve())
                }
                Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(RadiusTokens.L)).background(ColorTokens.BgSurface.resolve().copy(alpha = 0.92f))
                    .padding(SpacingTokens.M)) { WarStandings(war) { onOpen(ClanPage.Profile(it)) } }
                if (war.top.isNotEmpty()) {
                    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(RadiusTokens.L)).background(ColorTokens.BgSurface.resolve().copy(alpha = 0.92f))
                        .padding(SpacingTokens.M), verticalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
                        SectionLabel(stringResource(R.string.clanwar_our_fighters))
                        war.top.forEachIndexed { i, t ->
                            Row(Modifier.semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Sm)) {
                                TokenText(if (i == 0) "👑" else "${i + 1}.", TypographyTokens.BodyS, Modifier.width(28.dp))
                                Avatar(t.user.username, t.user.avatarPreset, size = 30.dp, frame = t.user.frame)
                                TokenText(t.user.username, TypographyTokens.BodyS, Modifier.weight(1f), maxLines = 1)
                                TokenText("${t.reps}", TypographyTokens.TitleS)
                            }
                        }
                    }
                }
                SecondaryButton(stringResource(R.string.clanwar_see_who_pushed), { onOpen(ClanPage.Fighters(war.id, null)) })
                TokenText(stringResource(R.string.clanwar_next_waiting), TypographyTokens.Caption, color = ColorTokens.TextSecondary.resolve(),
                    textAlign = TextAlign.Center)
                PrimaryButton(stringResource(R.string.clanwar_see_next), onContinue)
            }
        }
    }
}

/** Live war feed: who just scored for which clan. */
@Composable
internal fun WarFeed(feed: List<ClanWar.FeedItem>) {
    Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
        TokenText(stringResource(R.string.clan_war_live), TypographyTokens.LabelDisplay, color = ColorTokens.StateDanger.resolve())
        feed.take(8).forEach { f ->
            Row(Modifier.semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically) {
                TokenText(if (f.mine) "🔥" else "⚔️", TypographyTokens.BodyS, modifier = Modifier.clearAndSetSemantics {})
                Spacer(Modifier.width(SpacingTokens.Xs))
                TokenText(f.username, TypographyTokens.BodyS)
                Spacer(Modifier.width(SpacingTokens.Xs))
                TokenText(f.clanName, TypographyTokens.Caption, maxLines = 1, modifier = Modifier.weight(1f),
                    color = (if (f.mine) ColorTokens.BrandFlameText else ColorTokens.BrandVoltText).resolve())
                TokenText("+${f.points}", TypographyTokens.BodyS,
                    color = (if (f.mine) ColorTokens.StateSuccessText else ColorTokens.StateDanger).resolve())
            }
        }
    }
}
