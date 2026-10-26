package app.pushly.feature.social

import androidx.compose.foundation.background
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.style.TextAlign
import app.pushly.core.designsystem.ClanEmblem
import app.pushly.core.designsystem.GradientProgressBar
import app.pushly.core.designsystem.ProBadge
import app.pushly.core.designsystem.ProfileTarget
import app.pushly.core.designsystem.profileLink
import app.pushly.core.designsystem.generated.TokenColor
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import app.pushly.core.common.PLog
import app.pushly.core.common.PushPrompt
import app.pushly.core.common.ReportTarget
import app.pushly.core.common.Reporter
import app.pushly.core.common.SocialService
import app.pushly.core.designsystem.Avatar
import app.pushly.core.designsystem.BannerKind
import app.pushly.core.designsystem.InlineBanner
import app.pushly.core.designsystem.MinTouchTarget
import app.pushly.core.designsystem.Pill
import app.pushly.core.designsystem.PrimaryButton
import app.pushly.core.designsystem.ReportAction
import app.pushly.core.designsystem.TokenText
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.RadiusTokens
import app.pushly.core.designsystem.generated.SpacingTokens
import app.pushly.core.designsystem.generated.TypographyTokens
import app.pushly.core.designsystem.resolve
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** Player profile (doc 15 §1, P6-02). Same behaviour as iOS UserProfileModel. */
class UserProfileViewModel(
    private val service: SocialService,
    private val userId: String?,
    private val username: String?,
) : ViewModel() {
    data class UiState(val profile: UserProfile? = null, val loaded: Boolean = false, val failed: Boolean = false)

    private val _state = MutableStateFlow(UiState())
    val state: StateFlow<UiState> = _state.asStateFlow()

    fun load() {
        viewModelScope.launch { reload() }
    }

    private suspend fun reload() {
        try {
            val p = UserProfile.decode(service.userProfile(userId, username))
            _state.update { it.copy(profile = p, loaded = true) }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            PLog.error { "profile load failed: ${e.message}" }
            _state.update { it.copy(loaded = true) }
        }
    }

    private fun run(block: suspend (UserProfile) -> Unit) {
        val p = _state.value.profile ?: return
        viewModelScope.launch {
            try {
                block(p)
                _state.update { it.copy(failed = false) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.update { it.copy(failed = true) }
            }
            reload()
        }
    }

    fun addFriend() = run {
        service.sendFriendRequest(it.user.id)
        PushPrompt.request(PushPrompt.Reason.Friends)
    }

    fun accept() = run { service.respondFriendRequest(it.user.id, true) }
    fun block() = run { service.blockUser(it.user.id) }
}

@Composable
fun UserProfileScreen(vm: UserProfileViewModel, onBack: () -> Unit, modifier: Modifier = Modifier) {
    val s by vm.state.collectAsStateWithLifecycle()
    LaunchedEffect(vm) { vm.load() }
    var confirmBlock by remember { mutableStateOf(false) }
    val league = s.profile?.league?.league ?: "bronze"
    Box(modifier.fillMaxSize().background(ColorTokens.BgBase.resolve())) {
        Canvas(Modifier.fillMaxSize()) {
            drawRect(Brush.radialGradient(listOf(leagueColor(league).dark.copy(alpha = 0.28f), Color.Transparent),
                center = Offset(size.width / 2, size.height * 0.12f), radius = size.width))
        }
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = SpacingTokens.M, vertical = SpacingTokens.S),
            verticalArrangement = Arrangement.spacedBy(SpacingTokens.M),
        ) {
            TextButton(onClick = onBack, modifier = Modifier.heightIn(min = MinTouchTarget)) {
                Text(stringResource(R.string.social_back), color = ColorTokens.BrandFlameText.resolve())
            }
            val p = s.profile
            when {
                p != null -> ProfileContent(vm, p, s.failed) { confirmBlock = true }
                s.loaded -> Box(Modifier.fillMaxWidth().height(280.dp), contentAlignment = Alignment.Center) {
                    TokenText(stringResource(R.string.profile_unavailable), TypographyTokens.Body, color = ColorTokens.TextSecondary.resolve())
                }
                else -> Box(Modifier.fillMaxWidth().height(280.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = ColorTokens.BrandFlame.resolve())
                }
            }
        }
    }
    if (confirmBlock) {
        AlertDialog(
            containerColor = ColorTokens.BgElevated.resolve(),
            onDismissRequest = { confirmBlock = false },
            title = { Text(stringResource(R.string.profile_block_title)) },
            text = { Text(stringResource(R.string.profile_block_text)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmBlock = false
                    vm.block()
                    onBack()
                }) { Text(stringResource(R.string.social_block), color = ColorTokens.StateDanger.resolve()) }
            },
            dismissButton = { TextButton(onClick = { confirmBlock = false }) { Text(stringResource(R.string.social_cancel)) } },
        )
    }
}

internal fun leagueColor(league: String): TokenColor = when (league) {
    "bronze" -> ColorTokens.LeagueBronze
    "silver" -> ColorTokens.LeagueSilver
    "gold" -> ColorTokens.LeagueGold
    "platinum" -> ColorTokens.LeaguePlatinum
    "diamond" -> ColorTokens.LeagueDiamond
    else -> ColorTokens.LeagueChampion
}

private fun roleText(role: String): Int = when (role) {
    "leader" -> R.string.profile_role_leader
    "co_leader" -> R.string.profile_role_co_leader
    "elder" -> R.string.profile_role_elder
    else -> R.string.profile_role_member
}

@Composable
private fun ProfileContent(vm: UserProfileViewModel, p: UserProfile, failed: Boolean, onBlock: () -> Unit) {
    Hero(p)
    when (p.relation) {
        "none" -> PrimaryButton(stringResource(R.string.profile_add_friend), vm::addFriend)
        "incoming" -> PrimaryButton(stringResource(R.string.profile_accept), vm::accept)
        "outgoing" -> StatusPill("✉ " + stringResource(R.string.profile_request_sent), ColorTokens.TextSecondary, ColorTokens.BgSurface)
        "friends" -> StatusPill("✓ " + stringResource(R.string.profile_friends), ColorTokens.StateSuccessText, ColorTokens.StateSuccess)
    }
    if (failed) InlineBanner(stringResource(R.string.social_failed), BannerKind.Warning)
    val st = p.stats
    val h2h = p.headToHead?.takeIf { it.wins + it.losses + it.draws > 0 }
    if (st != null) {
        StatTiles(p, st)
        st.battles?.let { BattleCard(it) }
        h2h?.let { HeadToHeadCard(it, p.user.username) }
        st.last7?.takeIf { it.size == 7 }?.let { ActivityCard(it, st.repsWeek ?: it.sum(), st) }
        ProgressCard(st)
    } else {
        ProfileCard {
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                TokenText("🔒", TypographyTokens.TitleL, Modifier.clearAndSetSemantics {})
                TokenText(stringResource(if (p.relation == "friends") R.string.profile_private else R.string.profile_friends_only),
                    TypographyTokens.BodyS, color = ColorTokens.TextSecondary.resolve(), textAlign = TextAlign.Center)
            }
        }
        h2h?.let { HeadToHeadCard(it, p.user.username) }
    }
    if (p.relation != "self") {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            if (Reporter.isAvailable) ReportAction { reason -> Reporter.send(ReportTarget.User(p.user.id), reason) }
            Spacer(Modifier.weight(1f))
            TextButton(onClick = onBlock, modifier = Modifier.heightIn(min = MinTouchTarget)) {
                Text(stringResource(R.string.social_block), color = ColorTokens.StateDanger.resolve())
            }
        }
    }
    Spacer(Modifier.height(SpacingTokens.Xl))
}

@Composable
private fun StatusPill(text: String, color: TokenColor, bg: TokenColor) {
    Box(
        Modifier.fillMaxWidth().heightIn(min = MinTouchTarget).clip(CircleShape).background(bg.resolve().copy(alpha = 0.14f)),
        contentAlignment = Alignment.Center,
    ) { TokenText(text, TypographyTokens.TitleS, color = color.resolve()) }
}

/** Avatar with frame + level, name, PRO, league + trophies, clan chip (opens the clan). Same as iOS `ProfileHero`. */
@Composable
private fun Hero(p: UserProfile) {
    val u = p.user
    val tint = leagueColor(p.league.league).resolve()
    val level = p.stats?.level ?: u.level
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
        Box {
            Avatar(u.username, u.avatarPreset, size = 104.dp, frame = u.frame)
            val levelLabel = stringResource(R.string.social_level, level)
            Box(
                Modifier.align(Alignment.BottomEnd).size(32.dp).clip(CircleShape)
                    .background(Brush.linearGradient(listOf(ColorTokens.BrandFlame.resolve(), ColorTokens.BrandVolt.resolve())))
                    .border(3.dp, ColorTokens.BgBase.resolve(), CircleShape).semantics { contentDescription = levelLabel },
                contentAlignment = Alignment.Center,
            ) { TokenText("$level", TypographyTokens.LabelDisplay, color = ColorTokens.BgBase.resolve()) }
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
            TokenText(u.username, TypographyTokens.Name, maxLines = 1)
            if (u.pro == true) ProBadge()
        }
        Row(Modifier.semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
            TokenText("🛡 " + ProfileText.league(p.league), TypographyTokens.TitleS, color = tint)
            TokenText("🏆 ${u.trophies}", TypographyTokens.TitleS, color = ColorTokens.LeagueGold.resolve())
            u.country?.let(ProfileText::flag)?.let { TokenText(it, TypographyTokens.TitleS) }
        }
        p.clan?.let { c ->
            Row(
                Modifier.heightIn(min = MinTouchTarget).clip(CircleShape).background(ColorTokens.BgSurface.resolve().copy(alpha = 0.9f))
                    .border(1.dp, ColorTokens.StrokeSubtle.resolve(), CircleShape)
                    .profileLink(ProfileTarget.Clan(c.id)).padding(horizontal = SpacingTokens.M, vertical = SpacingTokens.Xs)
                    .semantics(mergeDescendants = true) {},
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S),
            ) {
                ClanEmblem(c.badge, c.tag, 30.dp)
                Column {
                    TokenText(c.name, TypographyTokens.TitleS, maxLines = 1)
                    TokenText(stringResource(roleText(c.role)) + " · 🛡 ${c.rating}", TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
                }
                TokenText("›", TypographyTokens.TitleM, color = ColorTokens.TextTertiary.resolve())
            }
        }
    }
}

@Composable
private fun StatTiles(p: UserProfile, st: UserProfile.Stats) {
    Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
        Row(Modifier.height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
            Tile("🏆", "${p.user.trophies}", stringResource(R.string.profile_tile_trophies), stringResource(R.string.profile_tile_best, st.bestTrophies),
                ColorTokens.LeagueGold, Modifier.weight(1f))
            Tile("🌍", st.rank?.let { "#$it" } ?: "–", stringResource(R.string.profile_tile_rank), stringResource(R.string.profile_tile_rank_sub),
                ColorTokens.BrandCyan, Modifier.weight(1f))
        }
        Row(Modifier.height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
            Tile("💪", "${st.repsTotal}", stringResource(R.string.profile_tile_pushups), stringResource(R.string.profile_tile_all_time),
                ColorTokens.BrandFlameText, Modifier.weight(1f))
            Tile("⭐", "${st.bestSet}", stringResource(R.string.profile_best_set), stringResource(R.string.profile_tile_one_go),
                ColorTokens.BrandVoltText, Modifier.weight(1f))
        }
    }
}

@Composable
private fun Tile(glyph: String, value: String, title: String, sub: String, tint: TokenColor, modifier: Modifier) {
    val shape = RoundedCornerShape(RadiusTokens.L)
    Column(
        modifier.fillMaxHeight().clip(shape).background(Brush.linearGradient(listOf(tint.resolve().copy(alpha = 0.14f), ColorTokens.BgSurface.resolve())))
            .border(1.dp, ColorTokens.StrokeSubtle.resolve(), shape).padding(SpacingTokens.M).semantics(mergeDescendants = true) {},
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        TokenText(glyph, TypographyTokens.TitleS, Modifier.clearAndSetSemantics {})
        TokenText(value, TypographyTokens.TitleL, color = tint.resolve(), maxLines = 1)
        TokenText(title, TypographyTokens.Caption)
        TokenText(sub, TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
    }
}

@Composable
private fun ProfileCard(content: @Composable () -> Unit) {
    val shape = RoundedCornerShape(RadiusTokens.L)
    Column(
        Modifier.fillMaxWidth().clip(shape).background(ColorTokens.BgSurface.resolve()).border(1.dp, ColorTokens.StrokeSubtle.resolve(), shape)
            .padding(SpacingTokens.M),
        verticalArrangement = Arrangement.spacedBy(SpacingTokens.S),
    ) { content() }
}

@Composable
private fun BattleCard(b: UserProfile.Battles) {
    ProfileCard {
        TokenText(stringResource(R.string.profile_battles), TypographyTokens.TitleS)
        Row(Modifier.semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(SpacingTokens.L)) {
            val track = Color.White.copy(alpha = 0.08f)
            val ring = ColorTokens.StateSuccess.resolve()
            Box(Modifier.size(88.dp), contentAlignment = Alignment.Center) {
                Canvas(Modifier.size(88.dp)) {
                    val stroke = Stroke(width = 9.dp.toPx(), cap = StrokeCap.Round)
                    drawArc(track, 0f, 360f, false, style = stroke)
                    drawArc(ring, -90f, (360 * b.winRate).toFloat(), false, style = stroke)
                }
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    TokenText(if (b.played == 0) "–" else "${Math.round(b.winRate * 100)}%", TypographyTokens.TitleL)
                    TokenText(stringResource(R.string.profile_win_rate), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
                    TokenText("${b.wins} W", TypographyTokens.TitleL, color = ColorTokens.StateSuccessText.resolve())
                    TokenText("${b.losses} L", TypographyTokens.TitleL, color = ColorTokens.StateDanger.resolve())
                    TokenText("${b.draws} D", TypographyTokens.TitleL, color = ColorTokens.TextSecondary.resolve())
                }
                if (b.form.isNotEmpty()) {
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        b.form.asReversed().forEach { o ->
                            val c = when (o) {
                                "W" -> ColorTokens.StateSuccessText
                                "L" -> ColorTokens.StateDanger
                                else -> ColorTokens.TextSecondary
                            }
                            Box(Modifier.size(14.dp).clip(RoundedCornerShape(3.dp)).background(c.resolve()), contentAlignment = Alignment.Center) {
                                TokenText(o, TypographyTokens.Overline, color = Color.Black.copy(alpha = 0.6f))
                            }
                        }
                    }
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
            if (b.winStreak > 1) Pill(stringResource(R.string.profile_win_streak, b.winStreak), color = ColorTokens.BrandFlameText)
            if (b.bestWinStreak > 0) Pill(stringResource(R.string.profile_best_win_streak, b.bestWinStreak), color = ColorTokens.TextSecondary)
        }
    }
}

@Composable
private fun HeadToHeadCard(h: UserProfile.HeadToHead, name: String) {
    val total = maxOf(h.wins + h.losses, 1)
    val a11y = stringResource(R.string.profile_h2h_line, h.wins, h.losses, h.draws)
    ProfileCard {
        Column(Modifier.clearAndSetSemantics { contentDescription = a11y }, verticalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
            TokenText(stringResource(R.string.profile_h2h), TypographyTokens.TitleS)
            Row(verticalAlignment = Alignment.CenterVertically) {
                TokenText(stringResource(R.string.profile_you), TypographyTokens.Caption, Modifier.weight(1f), color = ColorTokens.TextSecondary.resolve())
                TokenText("${h.wins} – ${h.losses}", TypographyTokens.TitleL)
                TokenText(name, TypographyTokens.Caption, Modifier.weight(1f), color = ColorTokens.TextSecondary.resolve(), maxLines = 1,
                    textAlign = TextAlign.End)
            }
            Row(Modifier.fillMaxWidth().height(8.dp), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                Box(Modifier.weight(maxOf(0.03f, h.wins.toFloat() / total)).fillMaxHeight().clip(CircleShape).background(ColorTokens.StateSuccessText.resolve()))
                Box(Modifier.weight(maxOf(0.03f, h.losses.toFloat() / total)).fillMaxHeight().clip(CircleShape).background(ColorTokens.StateDanger.resolve()))
            }
            if (h.draws > 0) TokenText(stringResource(R.string.profile_draws, h.draws), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
        }
    }
}

@Composable
private fun ActivityCard(days: List<Int>, week: Int, st: UserProfile.Stats) {
    val top = maxOf(days.maxOrNull() ?: 0, 1)
    val letters = ProfileText.lastWeekLetters()
    val hero = Brush.verticalGradient(listOf(ColorTokens.BrandFlame.resolve(), ColorTokens.BrandVolt.resolve()))
    val a11y = stringResource(R.string.profile_activity_a11y, week, st.wakeStreak ?: 0)
    ProfileCard {
        Column(Modifier.clearAndSetSemantics { contentDescription = a11y }, verticalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                TokenText(stringResource(R.string.profile_last7), TypographyTokens.TitleS, Modifier.weight(1f))
                TokenText(stringResource(R.string.profile_pushups_n, week), TypographyTokens.BodyS, color = ColorTokens.BrandFlameText.resolve())
            }
            Row(Modifier.fillMaxWidth().height(100.dp), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                days.forEachIndexed { i, v ->
                    Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        TokenText(if (v > 0) "$v" else "", TypographyTokens.Overline, color = ColorTokens.TextSecondary.resolve(), maxLines = 1)
                        Box(
                            Modifier.fillMaxWidth().height(maxOf(6f, 64f * v / top).dp).clip(RoundedCornerShape(4.dp))
                                .then(if (v > 0) Modifier.background(hero) else Modifier.background(Color.White.copy(alpha = 0.08f))),
                        )
                        TokenText(letters[i], TypographyTokens.Caption,
                            color = (if (i == 6) ColorTokens.TextPrimary else ColorTokens.TextTertiary).resolve())
                    }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                Pill(stringResource(R.string.profile_wake_streak, st.wakeStreak ?: 0), color = ColorTokens.BrandFlameText)
                Pill(stringResource(R.string.profile_tile_best, st.bestStreak), color = ColorTokens.TextSecondary)
            }
        }
    }
}

@Composable
private fun ProgressCard(st: UserProfile.Stats) {
    ProfileCard {
        TokenText(stringResource(R.string.profile_progress), TypographyTokens.TitleS)
        StatLine(stringResource(R.string.profile_level_label), st.level?.let { l -> "$l" + (st.xp?.let { " · $it XP" } ?: "") } ?: "–")
        StatLine(stringResource(R.string.profile_achievements), st.achievementsTotal?.let { "${st.achievements} / $it" } ?: "${st.achievements}")
        st.achievementsTotal?.takeIf { it > 0 }?.let { total ->
            GradientProgressBar(st.achievements.toFloat() / total, height = 6.dp)
        }
        StatLine(stringResource(R.string.profile_member_since), ProfileText.since(st.memberSince))
    }
}

@Composable
private fun StatLine(label: String, value: String) {
    Row(Modifier.fillMaxWidth().heightIn(min = 28.dp).semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically) {
        TokenText(label, TypographyTokens.BodyS, modifier = Modifier.weight(1f), color = ColorTokens.TextSecondary.resolve())
        TokenText(value, TypographyTokens.TitleS)
    }
}
