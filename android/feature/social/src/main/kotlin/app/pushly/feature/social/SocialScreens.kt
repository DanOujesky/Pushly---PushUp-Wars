package app.pushly.feature.social

import android.content.Intent
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.pushly.core.designsystem.ProBadge
import app.pushly.core.designsystem.AdBannerSlot
import app.pushly.core.designsystem.ArenaBackground
import app.pushly.core.designsystem.Avatar
import app.pushly.core.designsystem.BannerKind
import app.pushly.core.designsystem.InlineBanner
import app.pushly.core.designsystem.MinTouchTarget
import app.pushly.core.designsystem.Pill
import app.pushly.core.designsystem.ScreenTitle
import app.pushly.core.designsystem.SectionLabel
import app.pushly.core.designsystem.TokenText
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.RadiusTokens
import app.pushly.core.designsystem.generated.SpacingTokens
import app.pushly.core.designsystem.generated.TokenColor
import app.pushly.core.designsystem.generated.TypographyTokens
import app.pushly.core.designsystem.resolve

@Composable
private fun Chip(text: String, on: Boolean, onClick: () -> Unit) {
    Box(
        Modifier
            .heightIn(min = MinTouchTarget)
            .clip(CircleShape)
            .background(if (on) ColorTokens.BgElevated.resolve() else ColorTokens.BgSurface.resolve())
            .border(1.dp, if (on) ColorTokens.BrandFlame.resolve() else ColorTokens.StrokeSubtle.resolve(), CircleShape)
            .selectable(on, role = Role.Tab, onClick = onClick)
            .padding(horizontal = SpacingTokens.M),
        contentAlignment = Alignment.Center,
    ) {
        TokenText(text, TypographyTokens.BodyS, color = if (on) ColorTokens.TextPrimary.resolve() else ColorTokens.TextTertiary.resolve())
    }
}

@Composable
private fun SmallButton(text: String, color: TokenColor = ColorTokens.BrandFlame, onClick: () -> Unit) {
    Box(
        Modifier
            .heightIn(min = MinTouchTarget)
            .clip(CircleShape)
            .background(color.resolve().copy(alpha = 0.18f))
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = SpacingTokens.M),
        contentAlignment = Alignment.Center,
    ) { TokenText(text, TypographyTokens.BodyS, color = color.resolve()) }
}

@Composable
private fun UserRow(user: UserCard, onClick: (() -> Unit)? = null, trailing: @Composable () -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = MinTouchTarget)
            .then(if (onClick != null) Modifier.clickable(role = Role.Button, onClick = onClick) else Modifier),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(SpacingTokens.M),
    ) {
        Avatar(user.username, user.avatarPreset, size = 40.dp)
        Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
                TokenText(user.username, TypographyTokens.TitleS, maxLines = 1, modifier = Modifier.weight(1f, fill = false))
                if (user.pro == true) ProBadge()
            }
            TokenText(stringResource(R.string.social_level, user.level), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
        }
        trailing()
    }
}

@Composable
private fun Card(content: @Composable () -> Unit) {
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(RadiusTokens.L)).background(ColorTokens.BgSurface.resolve()).padding(SpacingTokens.M),
        verticalArrangement = Arrangement.spacedBy(SpacingTokens.S),
    ) { content() }
}

internal fun describe(item: FeedItem): Pair<Int, Any> = when (item.kind) {
    "wake_beaten" -> R.string.social_feed_wake to item.int("reps")
    "achievement" -> R.string.social_feed_achievement to item.text("title")
    "level_up" -> R.string.social_feed_level to item.int("level")
    "best_set" -> R.string.social_feed_best_set to item.int("reps")
    else -> R.string.social_feed_other to ""
}

/** Profile → Friends (doc 15 §1): feed with kudos, friends, requests, username search, share link. */
@Composable
fun FriendsScreen(
    vm: FriendsViewModel,
    myUsername: String?,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    onOpenProfile: (String) -> Unit = {},
) {
    val s by vm.state.collectAsStateWithLifecycle()
    var tab by rememberSaveable { mutableIntStateOf(0) }
    val context = LocalContext.current
    LaunchedEffect(vm) { vm.start() }

    ArenaBackground(modifier, glow = ColorTokens.BrandCyan, glowOffset = DpOffset(0.dp, (-260).dp)) {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(SpacingTokens.L),
            verticalArrangement = Arrangement.spacedBy(SpacingTokens.M),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = onBack, modifier = Modifier.heightIn(min = MinTouchTarget)) {
                    Text(stringResource(R.string.social_back), color = ColorTokens.BrandFlameText.resolve())
                }
                Spacer(Modifier.weight(1f))
                if (myUsername != null) {
                    val share = stringResource(R.string.social_share_text, "https://pushly.app/u/$myUsername")
                    TextButton(onClick = {
                        val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, share)
                        context.startActivity(Intent.createChooser(send, null))
                    }, modifier = Modifier.heightIn(min = MinTouchTarget)) {
                        Text(stringResource(R.string.social_share), color = ColorTokens.BrandFlameText.resolve())
                    }
                }
            }
            ScreenTitle(stringResource(R.string.social_friends_title), token = TypographyTokens.DisplayM)
            OutlinedTextField(
                value = s.query,
                onValueChange = vm::setQuery,
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                placeholder = { Text(stringResource(R.string.social_search_hint)) },
                colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = ColorTokens.BrandFlame.resolve()),
            )
            when (s.notice) {
                FriendsViewModel.Notice.RequestSent -> InlineBanner(stringResource(R.string.social_request_sent, s.noticeName), BannerKind.Info)
                FriendsViewModel.Notice.Failed -> InlineBanner(stringResource(R.string.social_failed), BannerKind.Warning)
                FriendsViewModel.Notice.None -> Unit
            }
            if (s.query.isNotBlank()) {
                SearchResults(s, vm)
                return@Column
            }
            Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                Chip(stringResource(R.string.social_tab_activity), tab == 0) { tab = 0 }
                Chip(stringResource(R.string.social_tab_friends), tab == 1) { tab = 1 }
            }
            if (!s.loaded) {
                Box(Modifier.fillMaxWidth().heightIn(min = 160.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = ColorTokens.BrandFlame.resolve())
                }
            } else if (tab == 0) {
                Feed(s, vm)
            } else {
                FriendLists(s, vm, onOpenProfile)
            }
        }
    }
}

@Composable
private fun SearchResults(s: FriendsViewModel.UiState, vm: FriendsViewModel) {
    SectionLabel(stringResource(R.string.social_search))
    Card {
        if (s.results.isEmpty()) {
            TokenText(
                stringResource(if (s.query.trim().length < 2) R.string.social_search_short else R.string.social_search_none),
                TypographyTokens.BodyS,
                color = ColorTokens.TextTertiary.resolve(),
            )
        }
        s.results.forEach { user ->
            UserRow(user) {
                when (user.relation) {
                    "friends" -> Pill(stringResource(R.string.social_is_friend), color = ColorTokens.StateSuccessText)
                    "outgoing" -> Pill(stringResource(R.string.social_requested))
                    "incoming" -> SmallButton(stringResource(R.string.social_accept)) { vm.respond(user, true) }
                    else -> SmallButton(stringResource(R.string.social_add)) { vm.add(user) }
                }
            }
        }
    }
}

@Composable
private fun Feed(s: FriendsViewModel.UiState, vm: FriendsViewModel) {
    SectionLabel(stringResource(R.string.social_last_7_days))
    Card {
        if (s.feed.isEmpty()) {
            TokenText(
                stringResource(if (s.list.friends.isEmpty()) R.string.social_feed_empty_no_friends else R.string.social_feed_empty),
                TypographyTokens.BodyS,
                color = ColorTokens.TextTertiary.resolve(),
            )
        }
        s.feed.forEach { item ->
            val (res, arg) = describe(item)
            val line = stringResource(res, arg)
            val kudosLabel = stringResource(if (item.kudosByMe) R.string.social_kudos_given else R.string.social_kudos_give, item.kudos)
            Row(
                Modifier.fillMaxWidth().heightIn(min = MinTouchTarget),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(SpacingTokens.M),
            ) {
                Avatar(item.user.username, item.user.avatarPreset, size = 40.dp)
                Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}) {
                    TokenText(item.user.username, TypographyTokens.TitleS, maxLines = 1)
                    TokenText(line, TypographyTokens.BodyS, color = ColorTokens.TextSecondary.resolve())
                }
                Box(
                    Modifier
                        .heightIn(min = MinTouchTarget)
                        .widthIn(min = MinTouchTarget)
                        .clip(CircleShape)
                        .background(if (item.kudosByMe) ColorTokens.BrandFlame.resolve().copy(alpha = 0.2f) else ColorTokens.BgElevated.resolve())
                        .clickable(enabled = !item.kudosByMe, role = Role.Button) { vm.giveKudos(item) }
                        .padding(horizontal = SpacingTokens.Sm)
                        .clearAndSetSemantics { contentDescription = kudosLabel },
                    contentAlignment = Alignment.Center,
                ) { TokenText("👊 ${item.kudos}", TypographyTokens.BodyS) }
            }
        }
    }
}

@Composable
private fun FriendLists(s: FriendsViewModel.UiState, vm: FriendsViewModel, onOpenProfile: (String) -> Unit) {
    if (s.list.incoming.isNotEmpty()) {
        SectionLabel(stringResource(R.string.social_requests))
        Card {
            s.list.incoming.forEach { user ->
                UserRow(user) {
                    Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                        SmallButton(stringResource(R.string.social_accept)) { vm.respond(user, true) }
                        SmallButton(stringResource(R.string.social_decline), ColorTokens.TextSecondary) { vm.respond(user, false) }
                    }
                }
            }
        }
    }
    SectionLabel(stringResource(R.string.social_friends_count, s.list.friends.size))
    Card {
        if (s.list.friends.isEmpty()) {
            TokenText(stringResource(R.string.social_no_friends), TypographyTokens.BodyS, color = ColorTokens.TextTertiary.resolve())
        }
        s.list.friends.forEach { user ->
            UserRow(user, onClick = { onOpenProfile(user.id) }) {
                Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S), verticalAlignment = Alignment.CenterVertically) {
                    user.streak?.takeIf { it > 0 }?.let { Pill("🔥 $it") }
                    SmallButton(stringResource(R.string.social_remove), ColorTokens.TextSecondary) { vm.remove(user.id) }
                    SmallButton(stringResource(R.string.social_block), ColorTokens.StateWarning) { vm.block(user.id) }
                }
            }
        }
    }
    if (s.list.outgoing.isNotEmpty()) {
        SectionLabel(stringResource(R.string.social_sent))
        Card {
            s.list.outgoing.forEach { user ->
                UserRow(user) { SmallButton(stringResource(R.string.social_cancel), ColorTokens.TextSecondary) { vm.remove(user.id) } }
            }
        }
    }
    if (s.list.blocked.isNotEmpty()) {
        SectionLabel(stringResource(R.string.social_blocked))
        Card {
            s.list.blocked.forEach { b ->
                Row(Modifier.fillMaxWidth().heightIn(min = MinTouchTarget), verticalAlignment = Alignment.CenterVertically) {
                    TokenText(b.username, TypographyTokens.BodyS, modifier = Modifier.weight(1f))
                    SmallButton(stringResource(R.string.social_unblock), ColorTokens.TextSecondary) { vm.unblock(b.id) }
                }
            }
        }
    }
}

/** Ranks tab (PS-60…PS-63, doc 08 §4): board, scope and period chips, top 100, own row pinned. */
@Composable
fun RanksScreen(vm: RanksViewModel, modifier: Modifier = Modifier) {
    val s by vm.state.collectAsStateWithLifecycle()
    LaunchedEffect(vm) { vm.start() }
    val unit = stringResource(
        when (s.board) {
            Board.Wake -> R.string.ranks_unit_points
            Board.Streak -> R.string.ranks_unit_days
            Board.Reps -> R.string.ranks_unit_reps
        },
    )
    ArenaBackground(modifier, glow = ColorTokens.LeagueGold, glowOffset = DpOffset(0.dp, (-260).dp)) {
        Column(Modifier.fillMaxSize()) {
            Column(
                Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(SpacingTokens.L),
                verticalArrangement = Arrangement.spacedBy(SpacingTokens.M),
            ) {
                ScreenTitle(stringResource(R.string.ranks_title), token = TypographyTokens.DisplayM)
                Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                    Board.entries.forEach { b ->
                        Chip(
                            stringResource(
                                when (b) {
                                    Board.Wake -> R.string.ranks_board_wake
                                    Board.Streak -> R.string.ranks_board_streak
                                    Board.Reps -> R.string.ranks_board_reps
                                },
                            ),
                            s.board == b,
                        ) { vm.selectBoard(b) }
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                    listOf("global" to R.string.ranks_global, "country" to R.string.ranks_country, "friends" to R.string.ranks_friends)
                        .forEach { (scope, label) -> Chip(stringResource(label), s.scope == scope) { vm.selectScope(scope) } }
                }
                if (s.board.periods.size > 1) {
                    Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                        s.board.periods.forEach { p ->
                            val label = when (p) {
                                "day" -> R.string.ranks_today
                                "week" -> R.string.ranks_week
                                "month" -> R.string.ranks_month
                                else -> R.string.ranks_all_time
                            }
                            Chip(stringResource(label), s.period == p) { vm.selectPeriod(p) }
                        }
                    }
                }
                TokenText(stringResource(R.string.ranks_utc), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
                val board = s.current
                when {
                    board != null -> {
                        if (board.needsCountry == true) InlineBanner(stringResource(R.string.ranks_needs_country), BannerKind.Info)
                        else if (board.rows.isEmpty()) TokenText(stringResource(R.string.ranks_empty), TypographyTokens.Body, color = ColorTokens.TextSecondary.resolve())
                        if (board.me?.shadow == true) InlineBanner(stringResource(R.string.ranks_shadow), BannerKind.Warning)
                        board.rows.forEach { RankRow(it, unit) }
                        if (board.around.isNotEmpty()) {
                            TokenText("···", TypographyTokens.Body, color = ColorTokens.TextTertiary.resolve())
                            board.around.forEach { RankRow(it, unit) }
                        }
                    }
                    s.failed -> InlineBanner(stringResource(R.string.ranks_failed), BannerKind.Warning)
                    else -> Box(Modifier.fillMaxWidth().heightIn(min = 200.dp), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = ColorTokens.BrandFlame.resolve())
                    }
                }
                // bottom of the list (doc 13 §1)
                AdBannerSlot("ranks_banner")
            }
            s.current?.pinnedMe?.let { me ->
                Box(Modifier.fillMaxWidth().background(ColorTokens.BgBase.resolve()).padding(horizontal = SpacingTokens.L, vertical = SpacingTokens.S)) {
                    RankRow(me, unit)
                }
            }
        }
    }
}

@Composable
private fun RankRow(row: Leaderboard.Row, unit: String) {
    val name = if (row.user.anonymous == true) {
        stringResource(R.string.ranks_anonymous)
    } else {
        row.user.username ?: stringResource(R.string.ranks_you)
    }
    val medal = when (row.rank) {
        1 -> ColorTokens.LeagueGold
        2 -> ColorTokens.LeagueSilver
        3 -> ColorTokens.LeagueBronze
        else -> ColorTokens.TextSecondary
    }
    val shape = RoundedCornerShape(RadiusTokens.M)
    val description = stringResource(R.string.ranks_row_a11y, row.rank, name, row.score, unit)
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 52.dp)
            .clip(shape)
            .background(if (row.isMe) ColorTokens.BgElevated.resolve() else ColorTokens.BgSurface.resolve())
            .border(1.dp, if (row.isMe) ColorTokens.BrandFlame.resolve() else ColorTokens.StrokeSubtle.resolve(), shape)
            .padding(horizontal = SpacingTokens.M)
            .clearAndSetSemantics { contentDescription = description },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(SpacingTokens.M),
    ) {
        TokenText("${row.rank}", TypographyTokens.TitleS, color = medal.resolve(), modifier = Modifier.widthIn(min = 36.dp))
        Avatar(name, row.user.avatarPreset, size = 36.dp)
        Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
            TokenText(name, TypographyTokens.BodyS, maxLines = 1, modifier = Modifier.weight(1f, fill = false))
            if (row.user.pro == true) ProBadge()
        }
        TokenText("${row.score}", TypographyTokens.TitleS)
    }
}
