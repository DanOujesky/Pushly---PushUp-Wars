package app.pushly.feature.clan

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.pushly.core.common.Monetization
import app.pushly.core.common.ReportTarget
import app.pushly.core.common.Reporter
import app.pushly.core.designsystem.AdBannerSlot
import app.pushly.core.designsystem.Avatar
import app.pushly.core.designsystem.BannerKind
import app.pushly.core.designsystem.ClanBadgeStyle
import app.pushly.core.designsystem.ClanEmblem
import app.pushly.core.designsystem.Cosmetics
import app.pushly.core.designsystem.GhostButton
import app.pushly.core.designsystem.GradientProgressBar
import app.pushly.core.designsystem.InlineBanner
import app.pushly.core.designsystem.MinTouchTarget
import app.pushly.core.designsystem.Pill
import app.pushly.core.designsystem.ProBadge
import app.pushly.core.designsystem.ReportDialog
import app.pushly.core.designsystem.SecondaryButton
import app.pushly.core.designsystem.SectionLabel
import app.pushly.core.designsystem.SideViewNotice
import app.pushly.core.designsystem.TokenText
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.RadiusTokens
import app.pushly.core.designsystem.generated.SpacingTokens
import app.pushly.core.designsystem.generated.TokenColor
import app.pushly.core.designsystem.generated.TypographyTokens
import app.pushly.core.designsystem.heroBrush
import app.pushly.core.designsystem.resolve
import kotlinx.coroutines.delay

@Composable
private fun noticeText(n: ClanViewModel.Notice): String? = when (n) {
    ClanViewModel.Notice.None -> null
    ClanViewModel.Notice.Requested -> stringResource(R.string.clan_notice_requested)
    ClanViewModel.Notice.Taken -> stringResource(R.string.clan_notice_taken)
    ClanViewModel.Notice.InvalidName -> stringResource(R.string.clan_notice_invalid_name)
    ClanViewModel.Notice.InvalidTag -> stringResource(R.string.clan_notice_invalid_tag)
    ClanViewModel.Notice.Full -> stringResource(R.string.clan_notice_full)
    ClanViewModel.Notice.Requirements -> stringResource(R.string.clan_notice_requirements)
    ClanViewModel.Notice.AlreadyInClan -> stringResource(R.string.clan_notice_already)
    ClanViewModel.Notice.RateLimited -> stringResource(R.string.clan_notice_slow)
    ClanViewModel.Notice.Failed -> stringResource(R.string.clan_notice_failed)
    ClanViewModel.Notice.Rallied -> stringResource(R.string.clan_notice_rallied)
    ClanViewModel.Notice.RallyCooldown -> stringResource(R.string.clan_notice_rally_cooldown)
    ClanViewModel.Notice.ProRequired -> stringResource(R.string.clan_notice_pro_emblem)
    ClanViewModel.Notice.InvalidBadge -> stringResource(R.string.clan_notice_invalid_badge)
}

@Composable
private fun roleLabel(r: ClanRole): String = stringResource(
    when (r) {
        ClanRole.Leader -> R.string.clan_role_leader
        ClanRole.CoLeader -> R.string.clan_role_co_leader
        ClanRole.Elder -> R.string.clan_role_elder
        ClanRole.Member -> R.string.clan_role_member
    },
)

internal fun badgeColor(c: ClanSummary): TokenColor = Cosmetics.badgeColor((c.badge ?: ClanBadgeStyle()).resolved(c.tag).color)

@Composable
private fun SmallButton(text: String, color: TokenColor = ColorTokens.BrandFlame, enabled: Boolean = true, onClick: () -> Unit) {
    Box(
        Modifier
            .heightIn(min = MinTouchTarget)
            .clip(CircleShape)
            .background(color.resolve().copy(alpha = 0.18f))
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = SpacingTokens.M),
        contentAlignment = Alignment.Center,
    ) { TokenText(text, TypographyTokens.BodyS, color = color.resolve()) }
}

@Composable
private fun Card(content: @Composable () -> Unit) {
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(RadiusTokens.L)).background(ColorTokens.BgSurface.resolve()).padding(SpacingTokens.M),
        verticalArrangement = Arrangement.spacedBy(SpacingTokens.S),
    ) { content() }
}

private enum class ClanSheet { Members, Chat, History, War, Settings, Discover, Create }

/**
 * Clan tab (doc 09 §4, D-074): a game lobby on one screen, like the Battle tab. In a clan: the badge, the war arena
 * (us vs them), today's push-ups for the clan, a big PUSH button and tiles for members, chat and wars. Without
 * a clan: find or create one. Everything else opens as a sheet. Static — nothing moves (D-072). Same as iOS.
 */
@Composable
fun ClanTabScreen(vm: ClanViewModel, modifier: Modifier = Modifier, onTrain: (() -> Unit)? = null) {
    val s by vm.state.collectAsStateWithLifecycle()
    var sheet by remember { mutableStateOf<ClanSheet?>(null) }
    LaunchedEffect(vm) { vm.start() }
    val home = s.home
    // joining or creating a clan closes the discovery / create sheet
    LaunchedEffect(home?.summary?.id) { if (home != null && (sheet == ClanSheet.Discover || sheet == ClanSheet.Create)) sheet = null }
    Box(modifier.fillMaxSize()) {
        ClanBackdrop(home?.summary?.let(::badgeColor) ?: ColorTokens.BrandCyan)
        when {
            !s.loaded -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = ColorTokens.BrandFlame.resolve())
            }
            home != null -> ClanLobby(vm, s, home, onTrain) { sheet = it }
            else -> JoinLobby(s) { sheet = it }
        }
        Toast(s, vm::clearNotice, Modifier.align(Alignment.TopCenter))
    }
    when (sheet) {
        ClanSheet.Members -> if (home != null) MembersSheet(vm, s, home) { sheet = null }
        ClanSheet.Chat -> ChatSheet(vm, s) { sheet = null }
        ClanSheet.History -> HistorySheet(s) { sheet = null }
        ClanSheet.War -> if (home != null && home.war != null) WarSheet(vm, home) { sheet = null }
        ClanSheet.Settings -> if (home != null) SettingsSheet(vm, s, home) { sheet = null }
        ClanSheet.Discover -> DiscoverSheet(vm, s) { sheet = null }
        ClanSheet.Create -> CreateSheet(vm, s) { sheet = null }
        null -> Unit
    }
}

@Composable
private fun ClanBackdrop(color: TokenColor) {
    val base = ColorTokens.BgBase.resolve()
    val glow = color.resolve()
    Canvas(Modifier.fillMaxSize()) {
        drawRect(base)
        drawRect(Brush.radialGradient(listOf(glow.copy(alpha = 0.3f), Color.Transparent),
            center = Offset(size.width / 2, size.height * 0.3f), radius = size.width))
        val horizon = size.height * 0.6f
        for (i in 0..8) {
            val t = i / 8f
            drawLine(Color.White.copy(alpha = 0.035f), Offset(size.width / 2, horizon), Offset(size.width * (t * 1.6f - 0.3f), size.height))
        }
    }
}

@Composable
private fun Toast(s: ClanViewModel.UiState, onDismiss: () -> Unit, modifier: Modifier) {
    val text = noticeText(s.notice) ?: return
    LaunchedEffect(s.notice) {
        delay(4000)
        onDismiss()
    }
    TokenText(
        text, TypographyTokens.BodyS,
        modifier
            .padding(horizontal = SpacingTokens.Gutter, vertical = SpacingTokens.Xs)
            .fillMaxWidth()
            .clip(RoundedCornerShape(RadiusTokens.M))
            .background(ColorTokens.BgElevated.resolve())
            .border(1.dp, ColorTokens.StrokeStrong.resolve(), RoundedCornerShape(RadiusTokens.M))
            .clickable(onClick = onDismiss)
            .padding(SpacingTokens.Sm),
    )
}

/** A lobby page: fits one screen; scrolls only when it can't (large text). */
@Composable
private fun LobbyColumn(content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit) {
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val minHeight = maxHeight
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .heightIn(min = minHeight)
                .padding(horizontal = SpacingTokens.Gutter, vertical = SpacingTokens.S),
            verticalArrangement = Arrangement.spacedBy(SpacingTokens.M),
            horizontalAlignment = Alignment.CenterHorizontally,
            content = content,
        )
    }
}

// ----------------------------------------------------------------------------- lobby (in a clan)

@Composable
private fun ClanLobby(vm: ClanViewModel, s: ClanViewModel.UiState, home: ClanHome, onTrain: (() -> Unit)?, open: (ClanSheet) -> Unit) {
    val role = s.myRole ?: ClanRole.Member
    LobbyColumn {
        TopBar(home, role) { open(ClanSheet.Settings) }
        Spacer(Modifier.weight(1f))
        val war = home.war
        Box(Modifier.clickable(role = Role.Button) { open(if (war == null) ClanSheet.Members else ClanSheet.War) }) {
            if (war != null) WarArena(war, home.summary) else IdleHero(home.summary)
        }
        val rally = war?.rally
        if (war != null && war.status == "live" && rally != null) RallyButton(rally.available, war.gap < 0, vm::rally)
        Spacer(Modifier.weight(1f))
        if (war != null && war.status == "live") MyWarDay(war.myToday)
        if (onTrain != null) PushButton(onTrain)
        val requests = if (role.canAcceptRequests) home.requests.size else 0
        val wins = s.warHistory.count { it.letter == "W" }
        val losses = s.warHistory.count { it.letter == "L" }
        Row(Modifier.height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
            LobbyTile("👥", stringResource(R.string.clan_members), "${home.summary.memberCount}/30", requests, ColorTokens.BrandCyan,
                Modifier.weight(1f)) { open(ClanSheet.Members) }
            LobbyTile("💬", stringResource(R.string.clan_tile_chat), stringResource(R.string.clan_tile_chat_sub), 0, ColorTokens.BrandLime,
                Modifier.weight(1f)) { open(ClanSheet.Chat) }
            LobbyTile("🏁", stringResource(R.string.clan_tile_wars),
                if (s.warHistory.isEmpty()) stringResource(R.string.clan_tile_wars_sub) else stringResource(R.string.clan_tile_wars_record, wins, losses),
                0, ColorTokens.BrandVolt, Modifier.weight(1f)) { open(ClanSheet.History) }
        }
    }
}

@Composable
private fun TopBar(home: ClanHome, role: ClanRole, onSettings: () -> Unit) {
    val color = badgeColor(home.summary)
    Row(Modifier.fillMaxWidth().heightIn(min = MinTouchTarget), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Sm)) {
        ClanEmblem(home.summary.badge, home.summary.tag, 40.dp)
        Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}) {
            TokenText(home.summary.name, TypographyTokens.TitleS, maxLines = 1)
            TokenText("${roleLabel(role)} · ${home.summary.memberCount}/30", TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve(), maxLines = 1)
        }
        val ratingLabel = stringResource(R.string.clan_rating_a11y, home.summary.rating)
        Row(
            Modifier.clip(CircleShape).background(Color.Black.copy(alpha = 0.35f)).border(1.dp, color.resolve().copy(alpha = 0.5f), CircleShape)
                .padding(horizontal = SpacingTokens.Sm, vertical = 6.dp).clearAndSetSemantics { contentDescription = ratingLabel },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Xs),
        ) {
            TokenText("🛡", TypographyTokens.BodyS)
            TokenText("${home.summary.rating}", TypographyTokens.TitleS)
        }
        val settingsLabel = stringResource(R.string.clan_settings)
        Box(
            Modifier.size(MinTouchTarget).clip(CircleShape).clickable(role = Role.Button, onClick = onSettings)
                .semantics { contentDescription = settingsLabel },
            contentAlignment = Alignment.Center,
        ) { TokenText("⚙️", TypographyTokens.TitleM, Modifier.clearAndSetSemantics {}) }
    }
}

/** Us vs them: both badges, the scores, a tug-of-war bar, time left and days won. */
@Composable
private fun WarArena(war: ClanWar, us: ClanSummary) {
    val ours = badgeColor(us).resolve()
    val them = war.opponent
    val theirs = them?.let { badgeColor(it).resolve() } ?: ColorTokens.StrokeStrong.resolve()
    val shape = RoundedCornerShape(RadiusTokens.L)
    val a11y = stringResource(R.string.clan_war_a11y, war.score.us, war.score.them)
    Column(
        Modifier.fillMaxWidth().clip(shape).background(ColorTokens.BgSurface.resolve().copy(alpha = 0.88f))
            .border(1.5.dp, Brush.horizontalGradient(listOf(ours.copy(alpha = 0.7f), theirs.copy(alpha = 0.7f))), shape)
            .padding(SpacingTokens.M)
            .semantics(mergeDescendants = true) { contentDescription = a11y },
        verticalArrangement = Arrangement.spacedBy(SpacingTokens.Sm),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
            TokenText(stringResource(if (war.status == "finished") R.string.clan_war_final_title else R.string.clan_war_title),
                TypographyTokens.Overline, color = ColorTokens.TextSecondary.resolve())
            if (war.status == "live") {
                TokenText(stringResource(R.string.clan_war_live_tag), TypographyTokens.Overline,
                    Modifier.clip(CircleShape).background(ColorTokens.StateDanger.resolve()).padding(horizontal = 6.dp, vertical = 1.dp),
                    color = Color.White)
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
            ArenaSide(us.badge, us.tag, us.name, war.score.us, ours, Modifier.weight(1f))
            Column(Modifier.widthIn(min = 64.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                TokenText("VS", TypographyTokens.DisplayM)
                warTimeLeft(war)?.let { TokenText(it, TypographyTokens.Caption, color = ColorTokens.BrandFlameText.resolve(), maxLines = 1) }
            }
            if (them != null) {
                ArenaSide(them.badge, them.tag, them.name, war.score.them, theirs, Modifier.weight(1f))
            } else {
                Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                    TokenText("💤", TypographyTokens.DisplayM)
                    TokenText(stringResource(R.string.clan_bye), TypographyTokens.TitleS, color = ColorTokens.TextSecondary.resolve())
                }
            }
        }
        TugBar(war.score.us, war.score.them, ours, theirs)
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            val gap = war.gap
            val line = when {
                them == null -> stringResource(R.string.clan_war_bye_line)
                war.status == "finished" -> stringResource(if (gap > 0) R.string.clan_war_victory else if (gap < 0) R.string.clan_war_defeat else R.string.clan_war_draw)
                gap > 0 -> stringResource(R.string.clan_war_ahead_by, gap)
                gap < 0 -> stringResource(R.string.clan_war_behind_by, -gap)
                else -> stringResource(R.string.clan_war_even)
            }
            TokenText(line, TypographyTokens.TitleS, Modifier.weight(1f),
                color = (if (gap > 0) ColorTokens.StateSuccessText else if (gap < 0) ColorTokens.StateDanger else ColorTokens.TextPrimary).resolve())
            val (won, lost) = war.daysWon
            if (won + lost > 0) Pill(stringResource(R.string.clan_days_short, won, lost))
            TokenText(" ›", TypographyTokens.TitleM, color = ColorTokens.TextTertiary.resolve())
        }
    }
}

@Composable
private fun ArenaSide(badge: ClanBadgeStyle?, tag: String, name: String, score: Int, color: Color, modifier: Modifier) {
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
        ClanEmblem(badge, tag, 64.dp)
        TokenText(name, TypographyTokens.LabelDisplay, color = color, maxLines = 1)
        TokenText("$score", TypographyTokens.DisplayM, maxLines = 1)
    }
}

@Composable
private fun TugBar(us: Int, them: Int, ours: Color, theirs: Color) {
    Canvas(Modifier.fillMaxWidth().height(14.dp).clearAndSetSemantics {}) {
        val share = if (us + them == 0) 0.5f else us.toFloat() / (us + them)
        val r = CornerRadius(size.height / 2, size.height / 2)
        drawRoundRect(Brush.horizontalGradient(listOf(theirs.copy(alpha = 0.7f), theirs)), cornerRadius = r)
        val w = maxOf(size.height, size.width * share)
        drawRoundRect(Brush.horizontalGradient(listOf(ours, ours.copy(alpha = 0.75f)), endX = w), size = size.copy(width = w), cornerRadius = r)
        val x = (size.width * share).coerceIn(1.5f, size.width - 1.5f)
        drawLine(Color.White, Offset(x, 0f), Offset(x, size.height), strokeWidth = 3.dp.toPx())
    }
}

@Composable
private fun IdleHero(summary: ClanSummary) {
    Column(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}, horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(SpacingTokens.Sm)) {
        ClanEmblem(summary.badge, summary.tag, 120.dp)
        TokenText(summary.name, TypographyTokens.TitleL, maxLines = 1)
        TokenText(stringResource(R.string.clan_war_next_monday), TypographyTokens.Caption, color = ColorTokens.TextSecondary.resolve(),
            textAlign = TextAlign.Center)
        if (summary.description.isNotBlank()) {
            TokenText(summary.description, TypographyTokens.BodyS, color = ColorTokens.TextTertiary.resolve(), textAlign = TextAlign.Center, maxLines = 2)
        }
    }
}

@Composable
private fun MyWarDay(today: ClanWar.Today) {
    Column(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TokenText(stringResource(R.string.clan_you_today), TypographyTokens.LabelDisplay, Modifier.weight(1f), color = ColorTokens.TextSecondary.resolve())
            TokenText(stringResource(R.string.clan_points, today.counted), TypographyTokens.TitleS, color = ColorTokens.BrandFlameText.resolve())
        }
        GradientProgressBar(if (today.fullCap > 0) minOf(1f, today.raw.toFloat() / today.fullCap) else 0f, height = 8.dp)
        TokenText(
            if (today.raw < today.fullCap) stringResource(R.string.clan_caps_line, today.fullCap, today.halfCap)
            else stringResource(R.string.clan_caps_full, today.halfCap),
            TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve(),
        )
    }
}

@Composable
private fun BigButton(title: String, subtitle: String, onClick: () -> Unit) {
    val flame = ColorTokens.BrandFlame.resolve()
    val shape = RoundedCornerShape(RadiusTokens.L)
    Column(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 80.dp)
            .drawBehind {
                drawRoundRect(flame.copy(alpha = 0.22f), topLeft = Offset(-8f, 4f),
                    size = androidx.compose.ui.geometry.Size(size.width + 16f, size.height + 16f),
                    cornerRadius = CornerRadius(RadiusTokens.L.toPx() + 8f))
            }
            .clip(shape)
            .background(heroBrush())
            .border(1.5.dp, Color.White.copy(alpha = 0.35f), shape)
            .clickable(role = Role.Button, onClick = onClick)
            .padding(vertical = SpacingTokens.Sm, horizontal = SpacingTokens.M),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        TokenText(title, TypographyTokens.DisplayM, color = Color.White, maxLines = 1)
        TokenText(subtitle, TypographyTokens.Overline, color = Color.White.copy(alpha = 0.85f))
    }
}

@Composable
private fun PushButton(onClick: () -> Unit) =
    BigButton(stringResource(R.string.clan_push_for_clan), stringResource(R.string.clan_push_sub), onClick)

@Composable
private fun RallyButton(available: Boolean, behind: Boolean, onClick: () -> Unit) {
    val bg = if (!available) ColorTokens.BgSurface else if (behind) ColorTokens.StateDanger else ColorTokens.BrandFlame
    Box(
        Modifier.heightIn(min = MinTouchTarget).clip(CircleShape).background(bg.resolve().copy(alpha = if (available) 0.85f else 0.7f))
            .clickable(enabled = available, role = Role.Button, onClick = onClick).padding(horizontal = SpacingTokens.M),
        contentAlignment = Alignment.Center,
    ) {
        TokenText(stringResource(if (available) R.string.clan_rally else R.string.clan_rally_used), TypographyTokens.TitleS,
            color = (if (available) ColorTokens.TextPrimary else ColorTokens.TextTertiary).resolve())
    }
}

@Composable
private fun LobbyTile(glyph: String, title: String, subtitle: String, badge: Int, tint: TokenColor, modifier: Modifier, onClick: () -> Unit) {
    val shape = RoundedCornerShape(RadiusTokens.M)
    val a11y = if (badge > 0) stringResource(R.string.clan_waiting_badge, badge) else ""
    Box(modifier) {
        Column(
            Modifier.fillMaxSize().heightIn(min = 88.dp).clip(shape).background(ColorTokens.BgSurface.resolve().copy(alpha = 0.9f))
                .border(1.dp, tint.resolve().copy(alpha = 0.35f), shape)
                .clickable(role = Role.Button, onClick = onClick)
                .semantics(mergeDescendants = true) { if (a11y.isNotEmpty()) contentDescription = "$title, $subtitle, $a11y" }
                .padding(vertical = SpacingTokens.Sm, horizontal = 2.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(SpacingTokens.Xs),
        ) {
            TokenText(glyph, TypographyTokens.TitleM, Modifier.clearAndSetSemantics {})
            TokenText(title, TypographyTokens.TitleS, maxLines = 1)
            TokenText(subtitle, TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve(), textAlign = TextAlign.Center, maxLines = 1)
        }
        if (badge > 0) {
            Box(
                Modifier.align(Alignment.TopEnd).offset(6.dp, (-6).dp).heightIn(min = 22.dp).widthIn(min = 22.dp).clip(CircleShape)
                    .background(ColorTokens.StateDanger.resolve()).clearAndSetSemantics {},
                contentAlignment = Alignment.Center,
            ) { TokenText(badge.toString(), TypographyTokens.Tab, color = Color.White) }
        }
    }
}

@Composable
private fun warTimeLeft(war: ClanWar): String? {
    if (war.status != "live") return null
    val end = runCatching { java.time.Instant.parse(war.endsAt).toEpochMilli() }.getOrNull() ?: return null
    val s = maxOf(0L, (end - System.currentTimeMillis()) / 1000)
    val d = (s / 86400).toInt()
    val h = ((s % 86400) / 3600).toInt()
    val m = ((s % 3600) / 60).toInt()
    return if (d > 0) stringResource(R.string.clan_war_left_days, d, h) else stringResource(R.string.clan_war_left_hours, h, m)
}

// ----------------------------------------------------------------------------- lobby without a clan

@Composable
private fun JoinLobby(s: ClanViewModel.UiState, open: (ClanSheet) -> Unit) {
    LobbyColumn {
        Row(Modifier.fillMaxWidth().heightIn(min = MinTouchTarget), verticalAlignment = Alignment.CenterVertically) {
            TokenText(stringResource(R.string.clan_title), TypographyTokens.DisplayM, Modifier.weight(1f))
        }
        Spacer(Modifier.weight(1f))
        ClanEmblem(ClanBadgeStyle("shield", "cyan", "fist"), "", 130.dp)
        TokenText(stringResource(R.string.clan_join_title), TypographyTokens.DisplayL)
        TokenText(stringResource(R.string.clan_join_pitch), TypographyTokens.Body, color = ColorTokens.TextSecondary.resolve(), textAlign = TextAlign.Center)
        Column(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(RadiusTokens.M)).background(ColorTokens.BgSurface.resolve().copy(alpha = 0.85f))
                .padding(SpacingTokens.M),
            verticalArrangement = Arrangement.spacedBy(SpacingTokens.S),
        ) {
            listOf("🏁" to R.string.clan_join_perk_war, "👥" to R.string.clan_join_perk_matched, "💬" to R.string.clan_join_perk_chat).forEach { (g, t) ->
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Sm)) {
                    TokenText(g, TypographyTokens.BodyS, Modifier.clearAndSetSemantics {})
                    TokenText(stringResource(t), TypographyTokens.BodyS)
                }
            }
        }
        Spacer(Modifier.weight(1f))
        BigButton(stringResource(R.string.clan_find), stringResource(R.string.clan_find_sub)) { open(ClanSheet.Discover) }
        SecondaryButton(stringResource(R.string.clan_create), { open(ClanSheet.Create) })
    }
}

// ----------------------------------------------------------------------------- sheets

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SheetFrame(title: String, onClose: () -> Unit, scroll: Boolean = true, content: @Composable () -> Unit) {
    ModalBottomSheet(
        onDismissRequest = onClose,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = ColorTokens.BgBase.resolve(),
    ) {
        Column(
            (if (scroll) Modifier.fillMaxWidth().verticalScroll(rememberScrollState()) else Modifier.fillMaxSize())
                .padding(horizontal = SpacingTokens.L)
                .padding(bottom = SpacingTokens.Xl),
            verticalArrangement = Arrangement.spacedBy(SpacingTokens.M),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                TokenText(title, TypographyTokens.TitleL, Modifier.weight(1f))
                GhostButton(stringResource(R.string.clan_done), onClose)
            }
            content()
        }
    }
}

@Composable
private fun DiscoverSheet(vm: ClanViewModel, s: ClanViewModel.UiState, onClose: () -> Unit) {
    LaunchedEffect(Unit) { vm.search() }
    SheetFrame(stringResource(R.string.clan_find_title), onClose) {
        noticeText(s.notice)?.let { InlineBanner(it, BannerKind.Info) }
        OutlinedTextField(
            value = s.query,
            onValueChange = vm::setQuery,
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            placeholder = { Text(stringResource(R.string.clan_search_hint)) },
            colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = ColorTokens.BrandFlame.resolve()),
        )
        SectionLabel(stringResource(if (s.query.isBlank()) R.string.clan_recommended else R.string.clan_results))
        Card {
            if (s.results.isEmpty()) TokenText(stringResource(R.string.clan_none), TypographyTokens.BodyS, color = ColorTokens.TextTertiary.resolve())
            s.results.forEach { c ->
                Row(
                    Modifier.fillMaxWidth().heightIn(min = MinTouchTarget),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(SpacingTokens.M),
                ) {
                    ClanEmblem(c.badge, c.tag, 44.dp)
                    Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}) {
                        TokenText(c.name, TypographyTokens.TitleS, maxLines = 1)
                        TokenText(stringResource(R.string.clan_line, c.memberCount, c.maxMembers, c.rating), TypographyTokens.Caption,
                            color = ColorTokens.TextTertiary.resolve())
                    }
                    when {
                        c.requested -> Pill(stringResource(R.string.clan_requested))
                        c.joinPolicy != "invite_only" && c.memberCount < c.maxMembers ->
                            SmallButton(stringResource(if (c.joinPolicy == "open") R.string.clan_join else R.string.clan_ask), enabled = !s.busy) {
                                vm.join(c)
                            }
                    }
                }
            }
        }
        // clan discovery only — never in the clan chat (doc 13 §1)
        AdBannerSlot("clan_banner")
    }
}

@Composable
private fun PolicyPicker(policy: String, onPick: (String) -> Unit) {
    listOf("open" to R.string.clan_policy_open, "request" to R.string.clan_policy_request, "invite_only" to R.string.clan_policy_invite)
        .forEach { (value, label) ->
            Row(
                Modifier.fillMaxWidth().heightIn(min = MinTouchTarget).selectable(policy == value, role = Role.RadioButton) { onPick(value) },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                TokenText(if (policy == value) "● " else "○ ", TypographyTokens.Body)
                TokenText(stringResource(label), TypographyTokens.Body)
            }
        }
}

@Composable
private fun CreateSheet(vm: ClanViewModel, s: ClanViewModel.UiState, onClose: () -> Unit) {
    var name by remember { mutableStateOf("") }
    var about by remember { mutableStateOf("") }
    var policy by remember { mutableStateOf("open") }
    var badge by remember { mutableStateOf(ClanBadgeStyle("shield", "flame", "flame")) }
    SheetFrame(stringResource(R.string.clan_new), onClose) {
        BadgeEditor(badge, name.ifBlank { "?" }) { badge = it }
        OutlinedTextField(name, { name = it.take(24) }, Modifier.fillMaxWidth(), label = { Text(stringResource(R.string.clan_name_hint)) }, singleLine = true)
        OutlinedTextField(about, { about = it.take(200) }, Modifier.fillMaxWidth(), label = { Text(stringResource(R.string.clan_about_hint)) })
        PolicyPicker(policy) { policy = it }
        noticeText(s.notice)?.let { TokenText(it, TypographyTokens.Caption, color = ColorTokens.StateDanger.resolve()) }
        app.pushly.core.designsystem.PrimaryButton(
            stringResource(R.string.clan_create_confirm),
            { vm.create(name, about, policy, badge, onClose) },
            enabled = name.trim().length >= 3 && !s.busy,
        )
    }
}

/** Live preview + shape, colour and emblem. Pro emblems (D-074) carry a PRO badge; free users get the paywall. */
@Composable
private fun BadgeEditor(style: ClanBadgeStyle, tag: String, onChange: (ClanBadgeStyle) -> Unit) {
    val r = style.resolved(tag)
    val isPro by Monetization.pro.collectAsState()
    Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.M), horizontalAlignment = Alignment.CenterHorizontally) {
        ClanEmblem(style, tag, 96.dp)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
            listOf("shield" to R.string.clan_shape_shield, "round" to R.string.clan_shape_round, "hex" to R.string.clan_shape_hex).forEach { (id, label) ->
                val on = r.shape == id
                Box(
                    Modifier.weight(1f).heightIn(min = MinTouchTarget).clip(RoundedCornerShape(RadiusTokens.M))
                        .background((if (on) ColorTokens.BrandFlame else ColorTokens.BgSurface).resolve().copy(alpha = if (on) 0.25f else 1f))
                        .border(1.dp, (if (on) ColorTokens.BrandFlame else ColorTokens.StrokeSubtle).resolve(), RoundedCornerShape(RadiusTokens.M))
                        .selectable(on, role = Role.RadioButton) { onChange(style.copy(shape = id)) },
                    contentAlignment = Alignment.Center,
                ) { TokenText(stringResource(label), TypographyTokens.BodyS) }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Cosmetics.badgeColors.forEach { c ->
                val on = r.color == c
                Box(
                    Modifier.size(MinTouchTarget).selectable(on, role = Role.RadioButton) { onChange(style.copy(color = c)) }
                        .semantics { contentDescription = c.replaceFirstChar { it.uppercase() } },
                    contentAlignment = Alignment.Center,
                ) {
                    Box(Modifier.size(30.dp).clip(CircleShape).background(Cosmetics.badgeColor(c).resolve())
                        .border(if (on) 3.dp else 0.dp, Color.White, CircleShape))
                }
            }
        }
        Cosmetics.emblems.chunked(4).forEach { row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
                row.forEach { e ->
                    val on = r.emblem.id == e.id
                    val locked = e.pro && !isPro && !on
                    val proHint = stringResource(R.string.clan_emblem_pro_hint)
                    Box(Modifier.weight(1f)) {
                        Box(
                            Modifier.fillMaxWidth().heightIn(min = 56.dp).clip(RoundedCornerShape(RadiusTokens.M))
                                .background(ColorTokens.BgElevated.resolve())
                                .border(if (on) 2.dp else 1.dp, (if (on) ColorTokens.BrandFlame else ColorTokens.StrokeSubtle).resolve(),
                                    RoundedCornerShape(RadiusTokens.M))
                                .selectable(on, role = Role.RadioButton) {
                                    if (locked) Monetization.showPaywall("emblem") else onChange(style.copy(emblem = e.id))
                                }
                                .semantics { contentDescription = if (locked) "${e.id}. $proHint" else e.id },
                            contentAlignment = Alignment.Center,
                        ) { Text(e.glyph, fontSize = 28.sp, modifier = Modifier.alpha(if (locked) 0.55f else 1f)) }
                        if (e.pro) ProBadge(Modifier.align(Alignment.TopEnd).offset(2.dp, (-4).dp))
                    }
                }
            }
        }
        if (!isPro) {
            TokenText(stringResource(R.string.clan_emblem_pro_note), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
        }
    }
}

@Composable
private fun SettingsSheet(vm: ClanViewModel, s: ClanViewModel.UiState, home: ClanHome, onClose: () -> Unit) {
    val role = s.myRole ?: ClanRole.Member
    val start = (home.summary.badge ?: ClanBadgeStyle()).resolved(home.summary.tag)
    var badge by remember { mutableStateOf(ClanBadgeStyle(start.shape, start.color, start.emblem.id)) }
    var about by remember { mutableStateOf(home.summary.description) }
    var policy by remember { mutableStateOf(home.summary.joinPolicy) }
    var confirmLeave by remember { mutableStateOf(false) }
    SheetFrame(stringResource(R.string.clan_settings), onClose) {
        if (role.canEditSettings) {
            BadgeEditor(badge, home.summary.tag) { badge = it }
            OutlinedTextField(about, { about = it.take(200) }, Modifier.fillMaxWidth(), label = { Text(stringResource(R.string.clan_about_hint)) })
            PolicyPicker(policy) { policy = it }
            noticeText(s.notice)?.let { TokenText(it, TypographyTokens.Caption, color = ColorTokens.StateDanger.resolve()) }
            app.pushly.core.designsystem.PrimaryButton(stringResource(R.string.clan_save), { vm.update(badge, about, policy, onClose) }, enabled = !s.busy)
        } else {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
                ClanEmblem(home.summary.badge, home.summary.tag, 56.dp)
                Column {
                    TokenText(home.summary.name, TypographyTokens.TitleM)
                    if (home.summary.description.isNotBlank()) {
                        TokenText(home.summary.description, TypographyTokens.BodyS, color = ColorTokens.TextSecondary.resolve())
                    }
                }
            }
            TokenText(stringResource(R.string.clan_settings_leaders_only), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
        }
        TextButton(onClick = { confirmLeave = true }, modifier = Modifier.fillMaxWidth().heightIn(min = MinTouchTarget)) {
            Text(
                stringResource(if (role == ClanRole.Leader && home.summary.memberCount == 1) R.string.clan_disband else R.string.clan_leave),
                color = ColorTokens.StateDanger.resolve(),
            )
        }
    }
    if (confirmLeave) {
        AlertDialog(
            containerColor = ColorTokens.BgElevated.resolve(),
            onDismissRequest = { confirmLeave = false },
            title = { Text(stringResource(R.string.clan_leave_confirm, home.summary.name)) },
            text = { Text(stringResource(R.string.clan_leave_text)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmLeave = false
                    vm.leave()
                    onClose()
                }) { Text(stringResource(R.string.clan_leave)) }
            },
            dismissButton = { TextButton(onClick = { confirmLeave = false }) { Text(stringResource(R.string.clan_cancel)) } },
        )
    }
}

@Composable
private fun MembersSheet(vm: ClanViewModel, s: ClanViewModel.UiState, home: ClanHome, onClose: () -> Unit) {
    val role = s.myRole ?: ClanRole.Member
    val ranked = home.members.sortedWith(compareByDescending<ClanHome.Member> { it.warReps }.thenByDescending { it.repsToday })
    SheetFrame(stringResource(R.string.clan_members), onClose) {
        if (ranked.size >= 3 && ranked[0].warReps > 0) Podium(ranked.take(3))
        if (role.canAcceptRequests && home.requests.isNotEmpty()) {
            SectionLabel(stringResource(R.string.clan_requests))
            Card {
                home.requests.forEach { r ->
                    Row(Modifier.fillMaxWidth().heightIn(min = MinTouchTarget), verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                        Avatar(r.user.username, r.user.avatarPreset, size = 36.dp, frame = r.user.frame)
                        Column(Modifier.weight(1f)) {
                            TokenText(r.user.username, TypographyTokens.TitleS)
                            r.message?.takeIf { it.isNotBlank() }?.let { TokenText(it, TypographyTokens.Caption) }
                        }
                        SmallButton(stringResource(R.string.clan_accept), enabled = !s.busy) { vm.respond(r.user.id, true) }
                        SmallButton(stringResource(R.string.clan_decline), ColorTokens.TextSecondary, enabled = !s.busy) { vm.respond(r.user.id, false) }
                    }
                }
            }
        }
        SectionLabel(stringResource(R.string.clan_members_count, home.summary.memberCount))
        Card { ranked.forEachIndexed { i, m -> MemberRow(vm, role, m, i + 1) } }
        TokenText(stringResource(R.string.clan_members_sorted), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
    }
}

@Composable
private fun Podium(top: List<ClanHome.Member>) {
    Row(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.Bottom,
        horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
        if (top.size > 1) PodiumStep(top[1], 2, 54, ColorTokens.LeagueSilver, Modifier.weight(1f))
        PodiumStep(top[0], 1, 76, ColorTokens.LeagueGold, Modifier.weight(1f))
        if (top.size > 2) PodiumStep(top[2], 3, 40, ColorTokens.LeagueBronze, Modifier.weight(1f))
    }
}

@Composable
private fun PodiumStep(m: ClanHome.Member, place: Int, height: Int, color: TokenColor, modifier: Modifier) {
    val c = color.resolve()
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
        if (place == 1) TokenText("👑", TypographyTokens.TitleL, Modifier.clearAndSetSemantics {})
        Avatar(m.user.username, m.user.avatarPreset, size = if (place == 1) 56.dp else 46.dp, frame = m.user.frame)
        TokenText(m.user.username, TypographyTokens.Caption, maxLines = 1)
        TokenText("${m.warReps}", TypographyTokens.TitleS, color = c)
        Box(
            Modifier.fillMaxWidth().height(height.dp).clip(RoundedCornerShape(RadiusTokens.S))
                .background(Brush.verticalGradient(listOf(c.copy(alpha = 0.8f), c.copy(alpha = 0.25f)))),
            contentAlignment = Alignment.Center,
        ) { TokenText("$place", TypographyTokens.DisplayM, color = Color.White.copy(alpha = 0.9f)) }
    }
}

@Composable
private fun MemberRow(vm: ClanViewModel, myRole: ClanRole, m: ClanHome.Member, place: Int) {
    var menu by remember { mutableStateOf(false) }
    val other = ClanRole.of(m.role) ?: ClanRole.Member
    val roles = myRole.assignable(other)
    val canKick = myRole.canKick(other)
    val canTransfer = myRole == ClanRole.Leader && other != ClanRole.Leader
    val hasActions = roles.isNotEmpty() || canKick || canTransfer
    Box {
        Row(
            Modifier
                .fillMaxWidth()
                .heightIn(min = MinTouchTarget)
                .clickable(enabled = hasActions, role = Role.Button) { menu = true }
                .semantics(mergeDescendants = true) {},
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S),
        ) {
            TokenText("$place", TypographyTokens.TitleS, Modifier.width(26.dp),
                color = (if (place <= 3) ColorTokens.LeagueGold else ColorTokens.TextTertiary).resolve())
            Avatar(m.user.username, m.user.avatarPreset, size = 40.dp, frame = m.user.frame)
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
                    TokenText(m.user.username, TypographyTokens.TitleS, maxLines = 1, modifier = Modifier.weight(1f, fill = false))
                    if (m.user.pro == true) ProBadge()
                }
                TokenText(roleLabel(other), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
            }
            Column(horizontalAlignment = Alignment.End) {
                TokenText(stringResource(R.string.clan_war_reps, m.warReps), TypographyTokens.BodyS)
                TokenText(stringResource(R.string.clan_today_reps, m.repsToday), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
            }
            if (hasActions) TokenText("⋯", TypographyTokens.TitleM, color = ColorTokens.TextSecondary.resolve())
        }
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            roles.forEach { r ->
                DropdownMenuItem(text = { Text(stringResource(R.string.clan_make_role, roleLabel(r))) }, onClick = {
                    menu = false
                    vm.setRole(m.user.id, r)
                })
            }
            if (canTransfer) {
                DropdownMenuItem(text = { Text(stringResource(R.string.clan_make_leader)) }, onClick = {
                    menu = false
                    vm.transfer(m.user.id)
                })
            }
            if (canKick) {
                DropdownMenuItem(text = { Text(stringResource(R.string.clan_kick), color = ColorTokens.StateDanger.resolve()) }, onClick = {
                    menu = false
                    vm.kick(m.user.id)
                })
            }
        }
    }
}

@Composable
private fun WarSheet(vm: ClanViewModel, home: ClanHome, onClose: () -> Unit) {
    val war = home.war ?: return
    SheetFrame(stringResource(R.string.clan_war), onClose) {
        WarArena(war, home.summary)
        val rally = war.rally
        if (war.status == "live" && rally != null) {
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { RallyButton(rally.available, war.gap < 0, vm::rally) }
        }
        if (war.status != "finished") SideViewNotice(compact = true)
        if (war.days.any { it.us + it.them > 0 }) Card { WarDays(war) }
        if (war.top.isNotEmpty() || war.theirTop.isNotEmpty()) Card { WarChampions(war, home.summary.name) }
        if (war.feed.isNotEmpty()) Card { WarFeed(war, home.summary.name) }
        TokenText(stringResource(R.string.clan_war_rules), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
    }
}

/** Points per war day, both sides (D-068). */
@Composable
private fun WarDays(war: ClanWar) {
    val (won, lost) = war.daysWon
    val top = maxOf(war.days.maxOfOrNull { maxOf(it.us, it.them) } ?: 1, 1)
    val a11y = stringResource(R.string.clan_days_won, won, lost)
    Column(Modifier.clearAndSetSemantics { contentDescription = a11y }, verticalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
        TokenText(a11y, TypographyTokens.LabelDisplay, color = ColorTokens.TextSecondary.resolve())
        Row(Modifier.fillMaxWidth().height(70.dp), verticalAlignment = Alignment.Bottom) {
            war.days.forEachIndexed { i, d ->
                Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                        Box(Modifier.width(7.dp).height(maxOf(3f, 48f * d.us / top).dp).clip(CircleShape).background(ColorTokens.BrandFlame.resolve()))
                        Box(Modifier.width(7.dp).height(maxOf(3f, 48f * d.them / top).dp).clip(CircleShape).background(ColorTokens.BrandVolt.resolve()))
                    }
                    TokenText(listOf("M", "T", "W", "T", "F", "S", "S")[i % 7], TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
                }
            }
        }
    }
}

/** Our best three vs theirs (D-068). */
@Composable
private fun WarChampions(war: ClanWar, ourName: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
        ChampionColumn(war.top.take(3), ourName, ColorTokens.BrandFlameText, Modifier.weight(1f))
        TokenText("⚔️", TypographyTokens.TitleM, modifier = Modifier.clearAndSetSemantics {})
        ChampionColumn(war.theirTop.take(3), war.opponent?.name ?: "–", ColorTokens.BrandVoltText, Modifier.weight(1f))
    }
}

@Composable
private fun ChampionColumn(rows: List<ClanWar.Top>, title: String, color: TokenColor, modifier: Modifier) {
    Column(modifier.semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
        TokenText(title, TypographyTokens.LabelDisplay, color = color.resolve())
        rows.forEachIndexed { i, r ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                TokenText(if (i == 0) "👑" else "${i + 1}.", TypographyTokens.Caption)
                Spacer(Modifier.width(SpacingTokens.Xs))
                TokenText(r.user.username, TypographyTokens.BodyS, modifier = Modifier.weight(1f), maxLines = 1)
                TokenText("${r.reps}", TypographyTokens.BodyS)
            }
        }
    }
}

/** Live war feed (D-068): who just scored for which side. */
@Composable
private fun WarFeed(war: ClanWar, ourName: String) {
    Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
        TokenText(stringResource(R.string.clan_war_live), TypographyTokens.LabelDisplay, color = ColorTokens.StateDanger.resolve())
        war.feed.take(8).forEach { f ->
            val ours = f.side == "us"
            Row(Modifier.semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically) {
                TokenText(if (ours) "🔥" else "⚔️", TypographyTokens.BodyS, modifier = Modifier.clearAndSetSemantics {})
                Spacer(Modifier.width(SpacingTokens.Xs))
                TokenText(f.username, TypographyTokens.BodyS)
                Spacer(Modifier.width(SpacingTokens.Xs))
                TokenText(if (ours) ourName else war.opponent?.name.orEmpty(), TypographyTokens.Caption, maxLines = 1,
                    color = (if (ours) ColorTokens.BrandFlameText else ColorTokens.BrandVoltText).resolve(), modifier = Modifier.weight(1f))
                TokenText("+${f.points}", TypographyTokens.BodyS,
                    color = (if (ours) ColorTokens.StateSuccessText else ColorTokens.StateDanger).resolve())
            }
        }
    }
}

/**
 * Clan chat (doc 09 §5, D-076): messenger-style bubbles — mine on the right in the brand gradient, others on the left with
 * avatar and name, day separators, system lines as small pills, big emoji reactions. Refreshes every 5 s while open.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ChatSheet(vm: ClanViewModel, s: ClanViewModel.UiState, onClose: () -> Unit) {
    var text by rememberSaveable { mutableStateOf("") }
    val list = rememberLazyListState()
    LaunchedEffect(Unit) {
        while (true) {
            vm.refreshMessages()
            delay(5000)
        }
    }
    val rows = remember(s.messages) {
        buildList {
            s.messages.forEachIndexed { i, m ->
                val prev = s.messages.getOrNull(i - 1)
                if (ChatLayout.newDay(m, prev)) add(ChatItem.Day(m.id, ChatLayout.instant(m.createdAt)))
                add(ChatItem.Msg(m, ChatLayout.startsGroup(m, prev)))
            }
        }
    }
    LaunchedEffect(rows.size) { if (rows.isNotEmpty()) list.animateScrollToItem(rows.size - 1) }
    ModalBottomSheet(
        onDismissRequest = onClose,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = ColorTokens.BgBase.resolve(),
    ) {
        Column(Modifier.fillMaxSize().imePadding()) {
            Row(Modifier.padding(horizontal = SpacingTokens.L).padding(bottom = SpacingTokens.S), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Sm)) {
                s.home?.summary?.let { ClanEmblem(it.badge, it.tag, 36.dp) }
                Column(Modifier.weight(1f)) {
                    TokenText(s.home?.summary?.name ?: stringResource(R.string.clan_chat), TypographyTokens.TitleM, maxLines = 1)
                    s.home?.summary?.let {
                        TokenText(stringResource(R.string.clan_chat_members, it.memberCount), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
                    }
                }
                GhostButton(stringResource(R.string.clan_done), onClose)
            }
            Box(Modifier.fillMaxWidth().height(1.dp).background(ColorTokens.StrokeSubtle.resolve()))
            if (rows.isEmpty()) {
                Column(Modifier.weight(1f).fillMaxWidth().padding(SpacingTokens.Xl), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(SpacingTokens.S, Alignment.CenterVertically)) {
                    Text("👋", fontSize = 48.sp, modifier = Modifier.clearAndSetSemantics {})
                    TokenText(stringResource(R.string.clan_chat_empty_title), TypographyTokens.TitleM)
                    TokenText(stringResource(R.string.clan_chat_empty_body), TypographyTokens.Caption, color = ColorTokens.TextSecondary.resolve(),
                        textAlign = TextAlign.Center)
                }
            } else {
                LazyColumn(Modifier.weight(1f).padding(horizontal = SpacingTokens.M), state = list,
                    verticalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
                    item { Spacer(Modifier.height(SpacingTokens.S)) }
                    items(rows, key = { it.key }) { row ->
                        when (row) {
                            is ChatItem.Day -> DaySeparator(row.at)
                            is ChatItem.Msg -> MessageRow(row.msg, mine = vm.myUserId != null && row.msg.user?.id == vm.myUserId, first = row.first)
                        }
                    }
                    item { Spacer(Modifier.height(SpacingTokens.S)) }
                }
            }
            noticeText(s.notice)?.let {
                TokenText(it, TypographyTokens.Caption, color = ColorTokens.StateDanger.resolve(), modifier = Modifier.padding(horizontal = SpacingTokens.L))
            }
            Column(
                Modifier.fillMaxWidth().background(ColorTokens.BgSurface.resolve()).padding(horizontal = SpacingTokens.M, vertical = SpacingTokens.S),
                verticalArrangement = Arrangement.spacedBy(SpacingTokens.Xs),
            ) {
                Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                    listOf("👊", "🔥", "💪").forEach { e ->
                        val label = stringResource(R.string.clan_send_reaction, e)
                        Box(
                            Modifier.widthIn(min = MinTouchTarget).heightIn(min = 40.dp).clip(CircleShape)
                                .background(ColorTokens.BgElevated.resolve())
                                .clickable(role = Role.Button) { vm.send(e, "kudos") }.semantics { contentDescription = label },
                            contentAlignment = Alignment.Center,
                        ) { Text(e, fontSize = 20.sp) }
                    }
                }
                Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                    OutlinedTextField(
                        text, { text = it.take(500) }, modifier = Modifier.weight(1f), maxLines = 5,
                        shape = RoundedCornerShape(22.dp),
                        placeholder = { Text(stringResource(R.string.clan_message_hint)) },
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedContainerColor = ColorTokens.BgElevated.resolve(),
                            unfocusedContainerColor = ColorTokens.BgElevated.resolve(),
                            unfocusedBorderColor = ColorTokens.StrokeSubtle.resolve(),
                            focusedBorderColor = ColorTokens.BrandFlame.resolve(),
                        ),
                    )
                    val sendLabel = stringResource(R.string.clan_send)
                    val enabled = text.isNotBlank()
                    Box(
                        Modifier
                            .padding(bottom = 4.dp)
                            .size(MinTouchTarget)
                            .clip(CircleShape)
                            .then(if (enabled) Modifier.background(heroBrush()) else Modifier.background(ColorTokens.StrokeStrong.resolve()))
                            .clickable(enabled = enabled, role = Role.Button) { vm.send(text) { text = "" } }
                            .semantics { contentDescription = sendLabel },
                        contentAlignment = Alignment.Center,
                    ) { Text("↑", color = Color.White, fontSize = 22.sp) }
                }
            }
        }
    }
}

private sealed interface ChatItem {
    val key: String

    data class Day(val id: Long, val at: java.time.Instant?) : ChatItem {
        override val key get() = "day-$id"
    }

    data class Msg(val msg: ClanMessage, val first: Boolean) : ChatItem {
        override val key get() = "msg-${msg.id}"
    }
}

@Composable
private fun DaySeparator(at: java.time.Instant?) {
    if (at == null) return
    val zone = java.time.ZoneId.systemDefault()
    val day = at.atZone(zone).toLocalDate()
    val today = java.time.LocalDate.now(zone)
    val label = when (day) {
        today -> stringResource(R.string.clan_chat_today)
        today.minusDays(1) -> stringResource(R.string.clan_chat_yesterday)
        else -> day.format(java.time.format.DateTimeFormatter.ofPattern("EEEE d MMMM", java.util.Locale.getDefault()))
    }
    Box(Modifier.fillMaxWidth().padding(vertical = SpacingTokens.S), contentAlignment = Alignment.Center) {
        TokenText(label, TypographyTokens.Caption, color = ColorTokens.TextSecondary.resolve(),
            modifier = Modifier.clip(CircleShape).background(ColorTokens.BgElevated.resolve()).padding(horizontal = SpacingTokens.Sm, vertical = 4.dp))
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun MessageRow(msg: ClanMessage, mine: Boolean, first: Boolean) {
    if (msg.kind == "system") {
        Box(Modifier.fillMaxWidth().padding(vertical = 2.dp), contentAlignment = Alignment.Center) {
            TokenText("🛡 " + (msg.body ?: ""), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve(), textAlign = TextAlign.Center,
                modifier = Modifier.clip(CircleShape).background(Color.White.copy(alpha = 0.04f)).padding(horizontal = SpacingTokens.Sm, vertical = 4.dp))
        }
        return
    }
    val name = msg.user?.username ?: stringResource(R.string.clan_deleted_user)
    val time = remember(msg.createdAt) {
        ChatLayout.instant(msg.createdAt)?.atZone(java.time.ZoneId.systemDefault())
            ?.format(java.time.format.DateTimeFormatter.ofLocalizedTime(java.time.format.FormatStyle.SHORT)) ?: ""
    }
    var reporting by remember { mutableStateOf(false) }
    val reportLabel = stringResource(R.string.clan_report_message)
    val canReport = Reporter.isAvailable && msg.user != null && !mine
    // Long press → report (doc 09 §5); TalkBack gets it as a custom action.
    Row(
        Modifier.fillMaxWidth().padding(top = if (first) SpacingTokens.S else 0.dp)
            .semantics(mergeDescendants = true) {
                if (canReport) customActions = listOf(CustomAccessibilityAction(reportLabel) { reporting = true; true })
            },
        horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S, if (mine) Alignment.End else Alignment.Start),
        verticalAlignment = Alignment.Bottom,
    ) {
        if (!mine) {
            if (first) Avatar(name, msg.user?.avatarPreset, size = 30.dp) else Spacer(Modifier.width(30.dp))
        }
        Column(Modifier.widthIn(max = 280.dp), horizontalAlignment = if (mine) Alignment.End else Alignment.Start,
            verticalArrangement = Arrangement.spacedBy(2.dp)) {
            if (first && !mine) {
                TokenText(name, TypographyTokens.Caption, color = ColorTokens.BrandCyan.resolve(), modifier = Modifier.padding(start = 4.dp))
            }
            val click = Modifier.combinedClickable(enabled = canReport, onLongClick = { reporting = true }, onClick = {})
            if (msg.kind == "kudos") {
                Text(msg.body ?: "", fontSize = 40.sp, modifier = click)
            } else {
                val shape = RoundedCornerShape(topStart = 18.dp, topEnd = 18.dp, bottomStart = if (mine) 18.dp else 6.dp, bottomEnd = if (mine) 6.dp else 18.dp)
                TokenText(
                    msg.body ?: "", TypographyTokens.Body,
                    color = if (mine) Color.White else ColorTokens.TextPrimary.resolve(),
                    modifier = click.clip(shape)
                        .then(if (mine) Modifier.background(heroBrush()) else Modifier.background(ColorTokens.BgElevated.resolve()))
                        .padding(horizontal = SpacingTokens.M, vertical = 9.dp),
                )
            }
            if (first || mine) {
                TokenText(time, TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve(), modifier = Modifier.padding(horizontal = 4.dp))
            }
        }
    }
    ReportDialog(reporting, onDismiss = { reporting = false }) { reason -> Reporter.send(ReportTarget.Message(msg.id), reason) }
}

@Composable
private fun HistorySheet(s: ClanViewModel.UiState, onClose: () -> Unit) {
    SheetFrame(stringResource(R.string.clan_war_history), onClose) {
        if (s.warHistory.isEmpty()) {
            TokenText(stringResource(R.string.clan_no_wars), TypographyTokens.BodyS, color = ColorTokens.TextTertiary.resolve())
        } else {
            WarStreak.current(s.warHistory)?.takeIf { it.second > 1 }?.let { (letter, n) ->
                Pill(stringResource(if (letter == "W") R.string.clan_streak_wins else R.string.clan_streak_losses, n),
                    color = if (letter == "W") ColorTokens.StateSuccessText else ColorTokens.TextSecondary)
            }
            Card { s.warHistory.forEach { WarHistoryRow(it) } }
        }
    }
}

@Composable
private fun WarHistoryRow(war: ClanWarRecord) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = MinTouchTarget).semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Sm),
    ) {
        TokenText(war.letter, TypographyTokens.TitleS, Modifier.width(24.dp), color = when (war.letter) {
            "W" -> ColorTokens.StateSuccessText
            "L" -> ColorTokens.StateDanger
            else -> ColorTokens.TextSecondary
        }.resolve())
        war.opponent?.let { ClanEmblem(it.badge, it.tag, 32.dp) }
        Column(Modifier.weight(1f)) {
            TokenText(war.opponent?.name ?: stringResource(R.string.clan_bye), TypographyTokens.BodyS, maxLines = 1)
            TokenText(war.weekStart, TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
        }
        TokenText("${war.us} : ${war.them}", TypographyTokens.BodyS)
    }
}
