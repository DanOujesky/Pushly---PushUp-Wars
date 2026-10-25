package app.pushly.feature.battle

import app.pushly.core.common.Monetization
import androidx.compose.runtime.collectAsState
import android.content.Intent
import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.TextButton
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import app.pushly.core.designsystem.PushlyTextField
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import app.pushly.core.common.AppActivity
import app.pushly.core.common.BattleService
import app.pushly.core.designsystem.Avatar
import app.pushly.core.designsystem.BannerKind
import app.pushly.core.designsystem.GhostButton
import app.pushly.core.designsystem.GradientProgressBar
import app.pushly.core.designsystem.InlineBanner
import app.pushly.core.designsystem.MinTouchTarget
import app.pushly.core.designsystem.PageDots
import app.pushly.core.designsystem.Pill
import app.pushly.core.designsystem.PrimaryButton
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
import app.pushly.core.designsystem.toTextStyle
import app.pushly.feature.wakeflow.SessionServices
import kotlinx.coroutines.delay

private enum class HubSheet { Friends, Practice, History, Ladder }

private val QuickModes = BattleMode.entries.filter { it.quickMatch }

/**
 * Battle tab (doc 07, D-071), same as iOS `BattleHubView`: one screen, no scrolling, like a game lobby. The arena shows
 * your league and trophies; pick a mode and hit BATTLE (ranked quick match — the only way to win or lose trophies).
 * Friends (always friendly), Practice (bots, ghosts) and History open as sheets. Battles take over the screen.
 */
@Composable
fun BattleHubScreen(
    vm: BattleHubViewModel,
    service: BattleService,
    sessions: SessionServices?,
    modifier: Modifier = Modifier,
    player: BattlePlayer? = null,
) {
    val s by vm.state.collectAsStateWithLifecycle()
    LaunchedEffect(vm) { vm.load() }
    var sheet by remember { mutableStateOf<HubSheet?>(null) }
    // a battle that starts from a sheet closes it
    LaunchedEffect(s.active?.id) { if (s.active != null) sheet = null }
    val active = s.active
    if (active != null) {
        val live = viewModel(key = "battle-${active.id}") { LiveBattleViewModel(active, service, sessions) }
        LiveBattleScreen(live, onClose = vm::closeBattle, onRematch = vm::rematch)
        return
    }
    val queued = s.queuedMode
    if (queued != null) {
        BackHandler(onBack = vm::cancelQueue)
        MatchmakingScreen(queued, s.waitedS, player, onCancel = vm::cancelQueue, onBot = vm::practiceInsteadOfWaiting)
        return
    }
    var modeWire by rememberSaveable { mutableStateOf(BattleMode.MaxReps.wire) }
    val mode = QuickModes.firstOrNull { it.wire == modeWire } ?: BattleMode.MaxReps

    Box(modifier.fillMaxSize()) {
        ArenaBackdrop(s.arena?.league ?: "bronze")
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
            ) {
                TopBar(player, s.arena) { sheet = HubSheet.Ladder }
                Spacer(Modifier.weight(1f))
                Box(Modifier.clickable(role = Role.Button) { sheet = HubSheet.Ladder }) { ArenaHero(s.arena) }
                Spacer(Modifier.weight(1f))
                s.invites.incoming.firstOrNull()?.let { inv ->
                    InviteBanner(inv, s.invites.incoming.size - 1, onFight = { vm.accept(inv) }, onDecline = { vm.decline(inv) })
                }
                ModePicker(mode) { modeWire = it.wire }
                BattleButton { vm.quickMatch(mode) }
                // same height for all three tiles, whatever their text
                Row(Modifier.height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Sm)) {
                    HubTile("👥", stringResource(R.string.hub_friends), stringResource(R.string.hub_friends_sub),
                        s.invites.incoming.size, ColorTokens.BrandCyan, Modifier.weight(1f)) { sheet = HubSheet.Friends }
                    HubTile("🤖", stringResource(R.string.hub_practice), stringResource(R.string.hub_practice_sub), 0,
                        ColorTokens.BrandLime, Modifier.weight(1f)) { sheet = HubSheet.Practice }
                    val r = s.arena?.record
                    HubTile("🕑", stringResource(R.string.battle_history),
                        if (r != null) stringResource(R.string.hub_history_sub, r.wins, r.losses) else stringResource(R.string.hub_history_empty),
                        0, ColorTokens.BrandVolt, Modifier.weight(1f)) { sheet = HubSheet.History }
                }
            }
        }
        Toast(s, vm::clearNotice, Modifier.align(Alignment.TopCenter))
    }

    when (sheet) {
        HubSheet.Friends -> FriendSheet(s, vm, player) { sheet = null }
        HubSheet.Practice -> PracticeSheet(vm, mode) { sheet = null }
        HubSheet.History -> HistorySheet(s) { sheet = null }
        HubSheet.Ladder -> LadderSheet(s.arena) { sheet = null }
        null -> Unit
    }
}

@Composable
internal fun modeBlurb(mode: BattleMode): String = stringResource(
    when (mode) {
        BattleMode.MaxReps -> R.string.mode_blurb_max
        BattleMode.Speed -> R.string.mode_blurb_speed
        BattleMode.BestOf3 -> R.string.mode_blurb_bo3
        BattleMode.Turns -> R.string.mode_blurb_turns
        BattleMode.Endurance -> R.string.mode_blurb_endurance
    },
)

internal fun leagueColor(league: String): TokenColor = when (league) {
    "bronze" -> ColorTokens.LeagueBronze
    "silver" -> ColorTokens.LeagueSilver
    "gold" -> ColorTokens.LeagueGold
    "platinum" -> ColorTokens.LeaguePlatinum
    "diamond" -> ColorTokens.LeagueDiamond
    else -> ColorTokens.LeagueChampion
}

// ------------------------------------------------------------------------------------------------ arena

/** Dark arena with a glow in the league's colour and faint floor lines. */
@Composable
private fun ArenaBackdrop(league: String) {
    val base = ColorTokens.BgBase.resolve()
    val glow = leagueColor(league).resolve()
    Canvas(Modifier.fillMaxSize()) {
        drawRect(base)
        drawRect(Brush.radialGradient(listOf(glow.copy(alpha = 0.32f), Color.Transparent),
            center = Offset(size.width / 2, size.height * 0.34f), radius = size.width * 0.95f))
        val horizon = size.height * 0.62f
        for (i in 0..8) {
            val t = i / 8f
            drawLine(Color.White.copy(alpha = 0.035f), Offset(size.width / 2, horizon), Offset(size.width * (t * 1.6f - 0.3f), size.height))
        }
        for (j in 1..5) {
            val y = horizon + (size.height - horizon) * Math.pow(j / 5.0, 1.6).toFloat()
            drawLine(Color.White.copy(alpha = 0.03f), Offset(0f, y), Offset(size.width, y))
        }
    }
}

@Composable
private fun TopBar(player: BattlePlayer?, arena: ArenaStatus?, onTrophies: () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = MinTouchTarget), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Sm)) {
        if (player != null) {
            Avatar(player.username, player.avatarPreset, size = 40.dp, frame = myFrame())
            Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}) {
                TokenText(player.username, TypographyTokens.TitleS, maxLines = 1)
                val streak = arena?.record?.winStreak ?: 0
                if (streak > 1) {
                    TokenText(stringResource(R.string.hub_streak, streak), TypographyTokens.Caption, color = ColorTokens.BrandFlameText.resolve())
                } else {
                    TokenText(stringResource(R.string.battle_title), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
                }
            }
        } else {
            TokenText(stringResource(R.string.battle_title), TypographyTokens.DisplayM, Modifier.weight(1f))
        }
        if (arena != null) {
            val a11y = stringResource(R.string.hub_trophies_a11y, arena.trophies)
            val gold = ColorTokens.LeagueGold.resolve()
            Row(
                Modifier.clip(CircleShape).background(Color.Black.copy(alpha = 0.35f)).border(1.dp, gold.copy(alpha = 0.5f), CircleShape)
                    .clickable(role = Role.Button, onClick = onTrophies)
                    .heightIn(min = MinTouchTarget)
                    .padding(horizontal = SpacingTokens.Sm, vertical = SpacingTokens.Xs + 2.dp)
                    .clearAndSetSemantics { contentDescription = a11y },
                horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Xs),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                TokenText("🏆", TypographyTokens.TitleS)
                TokenText(arena.trophies.toString(), TypographyTokens.TitleS)
            }
        }
    }
}

@Composable
private fun ArenaHero(arena: ArenaStatus?) {
    val league = arena?.league ?: "bronze"
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(SpacingTokens.Sm),
        modifier = Modifier.semantics(mergeDescendants = true) {}) {
        LeagueEmblem(league, arena?.tier)
        TokenText(leagueName(league, arena?.tier), TypographyTokens.LabelDisplay, color = leagueColor(league).resolve())
        if (arena != null) {
            GradientProgressBar(arena.progress, Modifier.widthIn(max = 260.dp).fillMaxWidth(), height = 10.dp)
            val next = arena.next
            TokenText(
                if (next != null) stringResource(R.string.hub_to_next, next.at - arena.trophies, leagueName(next.league, next.tier))
                else stringResource(R.string.hub_top),
                TypographyTokens.Caption, color = ColorTokens.TextSecondary.resolve(),
            )
            Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                arena.rank?.let { Pill(stringResource(R.string.hub_rank, it), color = ColorTokens.BrandFlameText) }
                arena.seasonDaysLeft()?.let { Pill(stringResource(R.string.hub_season, it)) }
            }
            TokenText(stringResource(R.string.hub_all_leagues), TypographyTokens.Caption, color = ColorTokens.BrandFlameText.resolve())
        } else {
            TokenText(stringResource(R.string.hub_no_arena), TypographyTokens.Caption, color = ColorTokens.TextSecondary.resolve(),
                textAlign = TextAlign.Center)
        }
    }
}

/** A shield in the league's colour with the tier and a soft halo behind it. Static (D-072: the lobby doesn't move). */
@Composable
private fun LeagueEmblem(league: String, tier: String?) {
    val color = leagueColor(league).resolve()
    Box(Modifier.size(150.dp, 162.dp).clearAndSetSemantics {}, contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(170.dp)) {
            val rays = Brush.sweepGradient(
                listOf(color.copy(alpha = 0f), color.copy(alpha = 0.35f), color.copy(alpha = 0f), color.copy(alpha = 0.35f), color.copy(alpha = 0f)),
            )
            drawCircle(rays, radius = size.minDimension / 2)
        }
        Canvas(Modifier.size(120.dp, 136.dp).shadow(24.dp, CircleShape, ambientColor = color, spotColor = color, clip = false)) {
            val w = size.width
            val h = size.height
            val shield = Path().apply {
                moveTo(w / 2, 0f)
                lineTo(w, h * 0.16f)
                lineTo(w * 0.96f, h * 0.56f)
                quadraticTo(w * 0.86f, h * 0.86f, w / 2, h)
                quadraticTo(w * 0.14f, h * 0.86f, w * 0.04f, h * 0.56f)
                lineTo(0f, h * 0.16f)
                close()
            }
            drawPath(shield, Brush.verticalGradient(listOf(color, color.copy(alpha = 0.55f))))
            drawPath(shield, Color.White.copy(alpha = 0.35f), style = Stroke(width = 2.dp.toPx()))
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.offset(y = (-6).dp)) {
            TokenText(leagueGlyph(league), TypographyTokens.DisplayM, style = TypographyTokens.DisplayM.toTextStyle().copy(fontSize = 40.sp))
            if (tier != null) TokenText(tier, TypographyTokens.DisplayM, color = Color.White)
        }
    }
}

@Composable
private fun ModePicker(mode: BattleMode, onChange: (BattleMode) -> Unit) {
    val index = QuickModes.indexOf(mode).coerceAtLeast(0)
    val prev = { onChange(QuickModes[(index + QuickModes.size - 1) % QuickModes.size]) }
    val next = { onChange(QuickModes[(index + 1) % QuickModes.size]) }
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
        RoundIcon("‹", stringResource(R.string.hub_prev_mode), prev)
        Column(
            Modifier.weight(1f).pointerInput(index) {
                var dx = 0f
                detectHorizontalDragGestures(onDragStart = { dx = 0f }, onDragEnd = {
                    if (dx < -60) next() else if (dx > 60) prev()
                }) { _, amount -> dx += amount }
            },
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            TokenText(modeTitle(mode.wire, mode.variant), TypographyTokens.TitleM)
            TokenText(modeBlurb(mode), TypographyTokens.Caption, color = ColorTokens.TextSecondary.resolve(), textAlign = TextAlign.Center)
            PageDots(QuickModes.size, index, Modifier.padding(top = SpacingTokens.Xs))
        }
        RoundIcon("›", stringResource(R.string.hub_next_mode), next)
    }
}

@Composable
private fun RoundIcon(glyph: String, label: String, onClick: () -> Unit) {
    Box(
        Modifier.size(MinTouchTarget).clip(CircleShape).background(Color.White.copy(alpha = 0.06f))
            .clickable(role = Role.Button, onClick = onClick).semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) { TokenText(glyph, TypographyTokens.TitleM, Modifier.clearAndSetSemantics {}) }
}

/** The big call to action: ranked quick match. */
@Composable
private fun BattleButton(onClick: () -> Unit) {
    val flame = ColorTokens.BrandFlame.resolve()
    val shape = RoundedCornerShape(RadiusTokens.L)
    Column(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 88.dp)
            .drawBehind {
                drawRoundRect(flame.copy(alpha = 0.22f), topLeft = Offset(-8f, 4f),
                    size = androidx.compose.ui.geometry.Size(size.width + 16f, size.height + 16f),
                    cornerRadius = androidx.compose.ui.geometry.CornerRadius(RadiusTokens.L.toPx() + 8f))
            }
            .clip(shape)
            .background(heroBrush())
            .border(1.5.dp, Color.White.copy(alpha = 0.35f), shape)
            .clickable(role = Role.Button, onClick = onClick)
            .padding(vertical = SpacingTokens.Sm),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        TokenText(stringResource(R.string.hub_battle), TypographyTokens.DisplayL, color = Color.White)
        TokenText(stringResource(R.string.hub_ranked_sub), TypographyTokens.Overline, color = Color.White.copy(alpha = 0.85f))
    }
}

@Composable
private fun HubTile(glyph: String, title: String, subtitle: String, badge: Int, tint: TokenColor, modifier: Modifier, onClick: () -> Unit) {
    val shape = RoundedCornerShape(RadiusTokens.M)
    val a11y = if (badge > 0) stringResource(R.string.hub_waiting_badge, badge) else ""
    Box(modifier) {
        Column(
            Modifier.fillMaxSize().heightIn(min = 96.dp).clip(shape).background(ColorTokens.BgSurface.resolve().copy(alpha = 0.9f))
                .border(1.dp, tint.resolve().copy(alpha = 0.35f), shape)
                .clickable(role = Role.Button, onClick = onClick)
                .semantics(mergeDescendants = true) { if (a11y.isNotEmpty()) contentDescription = "$title, $subtitle, $a11y" }
                .padding(vertical = SpacingTokens.Sm, horizontal = SpacingTokens.Xs),
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
private fun InviteBanner(inv: BattleInvites.Incoming, more: Int, onFight: () -> Unit, onDecline: () -> Unit) {
    val shape = RoundedCornerShape(RadiusTokens.M)
    Row(
        Modifier.fillMaxWidth().clip(shape).background(ColorTokens.BgElevated.resolve()).border(1.5.dp, ColorTokens.BrandCyan.resolve(), shape)
            .padding(horizontal = SpacingTokens.Sm, vertical = SpacingTokens.Xs),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Sm),
    ) {
        Avatar(inv.from.username, inv.from.avatarPreset, size = 36.dp)
        Column(Modifier.weight(1f)) {
            TokenText(stringResource(R.string.hub_challenges_you, inv.from.username), TypographyTokens.TitleS, maxLines = 1)
            TokenText(modeTitle(inv.mode, inv.variant) + if (more > 0) " · +$more" else "", TypographyTokens.Caption,
                color = ColorTokens.TextSecondary.resolve())
        }
        RoundIcon("✕", stringResource(R.string.hub_decline), onDecline)
        Box(
            Modifier.heightIn(min = MinTouchTarget).clip(CircleShape).background(heroBrush())
                .clickable(role = Role.Button, onClick = onFight).padding(horizontal = SpacingTokens.M),
            contentAlignment = Alignment.Center,
        ) { TokenText(stringResource(R.string.battle_fight), TypographyTokens.Button, color = Color.White) }
    }
}

@Composable
private fun Toast(s: BattleHubViewModel.UiState, onDismiss: () -> Unit, modifier: Modifier) {
    val text = noticeText(s)
    LaunchedEffect(s.notice) {
        if (s.notice != BattleHubViewModel.Notice.None) {
            delay(4000)
            onDismiss()
        }
    }
    if (text != null) {
        val shape = RoundedCornerShape(RadiusTokens.M)
        TokenText(
            text, TypographyTokens.BodyS,
            Modifier.fillMaxWidth().clip(shape).background(ColorTokens.BgElevated.resolve())
                .border(1.dp, ColorTokens.StrokeStrong.resolve(), shape).clickable(onClick = onDismiss).padding(SpacingTokens.Sm),
        )
    }
}

@Composable
private fun noticeText(s: BattleHubViewModel.UiState): String? = when (s.notice) {
    BattleHubViewModel.Notice.QueueFailed -> stringResource(R.string.battle_queue_failed)
    BattleHubViewModel.Notice.NobodyFound -> stringResource(R.string.battle_nobody)
    BattleHubViewModel.Notice.ChallengeSent -> stringResource(R.string.battle_challenge_sent, s.noticeName)
    BattleHubViewModel.Notice.ChallengeFailed -> stringResource(R.string.battle_challenge_failed)
    BattleHubViewModel.Notice.Expired -> stringResource(R.string.battle_expired)
    BattleHubViewModel.Notice.GhostLimit -> stringResource(R.string.battle_ghost_limit)
    BattleHubViewModel.Notice.NoGhost -> stringResource(R.string.battle_no_ghost)
    BattleHubViewModel.Notice.BotFailed -> stringResource(R.string.bot_failed)
    BattleHubViewModel.Notice.FriendRequested -> stringResource(R.string.friends_request_sent, s.noticeName)
    BattleHubViewModel.Notice.FriendRequestFailed -> stringResource(R.string.friends_request_failed)
    BattleHubViewModel.Notice.None -> null
}

// ------------------------------------------------------------------------------------------------ matchmaking

/** Full-screen search: you in a ring, the mode, a timer; a bot after 15 s. Only the timer changes. */
@Composable
private fun MatchmakingScreen(mode: BattleMode, waitedS: Int, player: BattlePlayer?, onCancel: () -> Unit, onBot: () -> Unit) {
    DisposableEffect(Unit) {
        AppActivity.battlePhase = "matchmaking"
        onDispose { if (AppActivity.battlePhase == "matchmaking") AppActivity.battlePhase = "none" }
    }
    val flame = ColorTokens.BrandFlame.resolve()
    Column(
        Modifier.fillMaxSize().background(ColorTokens.BgBase.resolve()).verticalScroll(rememberScrollState()).padding(SpacingTokens.L),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(SpacingTokens.M),
    ) {
        Spacer(Modifier.height(SpacingTokens.Xl))
        Box(Modifier.size(220.dp).clearAndSetSemantics {}, contentAlignment = Alignment.Center) {
            Canvas(Modifier.fillMaxSize()) {
                for (i in 0..2) {
                    drawCircle(flame.copy(alpha = 0.5f - i * 0.15f), radius = size.minDimension / 2 * (0.55f + i * 0.22f), style = Stroke(2.dp.toPx()))
                }
            }
            if (player != null) Avatar(player.username, player.avatarPreset, size = 96.dp, frame = myFrame()) else TokenText("⚡", TypographyTokens.DisplayL)
        }
        TokenText(stringResource(R.string.hub_searching), TypographyTokens.DisplayM, textAlign = TextAlign.Center)
        TokenText(modeTitle(mode.wire, mode.variant), TypographyTokens.TitleS, color = ColorTokens.BrandFlameText.resolve())
        TokenText("%d:%02d".format(waitedS / 60, waitedS % 60), TypographyTokens.Stat)
        TokenText(stringResource(R.string.hub_searching_note), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve(),
            textAlign = TextAlign.Center)
        SideViewNotice(compact = true)
        Spacer(Modifier.height(SpacingTokens.Xl))
        if (waitedS >= 15) SecondaryButton(stringResource(R.string.bot_nobody_yet), onBot)
        GhostButton(stringResource(R.string.battle_cancel), onCancel)
    }
}

// ------------------------------------------------------------------------------------------------ sheets

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun HubSheetFrame(title: String, onClose: () -> Unit, content: @Composable () -> Unit) {
    ModalBottomSheet(
        onDismissRequest = onClose,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = ColorTokens.BgBase.resolve(),
    ) {
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = SpacingTokens.L)
                .padding(bottom = SpacingTokens.Xl),
            verticalArrangement = Arrangement.spacedBy(SpacingTokens.M),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                TokenText(title, TypographyTokens.TitleL, Modifier.weight(1f))
                GhostButton(stringResource(R.string.hub_close), onClose)
            }
            content()
        }
    }
}

/** Friendly battles (D-071): pick a mode, challenge a friend. Never changes trophies. */
@Composable
private fun FriendSheet(s: BattleHubViewModel.UiState, vm: BattleHubViewModel, player: BattlePlayer?, onClose: () -> Unit) {
    var mode by rememberSaveable { mutableStateOf(BattleMode.MaxReps.wire) }
    val m = BattleMode.of(mode) ?: BattleMode.MaxReps
    HubSheetFrame(stringResource(R.string.friendly_title), onClose) {
        InlineBanner(stringResource(R.string.friendly_note), BannerKind.Info)
        if (s.invites.incoming.isNotEmpty()) {
            SectionLabel(stringResource(R.string.battle_for_you))
            s.invites.incoming.forEach { inv -> InviteBanner(inv, 0, onFight = { vm.accept(inv) }, onDecline = { vm.decline(inv) }) }
        }
        SectionLabel(stringResource(R.string.friendly_mode))
        ModeChips(BattleMode.entries, m) { mode = it.wire }
        TokenText(modeBlurb(m), TypographyTokens.Caption, color = ColorTokens.TextSecondary.resolve())
        SectionLabel(stringResource(R.string.battle_challenge))
        if (s.friends.isEmpty()) {
            TokenText(stringResource(R.string.friends_none_yet), TypographyTokens.BodyS, color = ColorTokens.TextTertiary.resolve())
        }
        s.friends.forEach { f ->
            Row(Modifier.fillMaxWidth().heightIn(min = MinTouchTarget), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Sm)) {
                Avatar(f.username, f.avatarPreset, size = 40.dp)
                TokenText(f.username, TypographyTokens.TitleS, Modifier.weight(1f), maxLines = 1)
                if (s.invites.outgoing.any { it.to?.id == f.id && it.status == "pending" }) {
                    TokenText(stringResource(R.string.friendly_waiting), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
                }
                Box(
                    Modifier.heightIn(min = MinTouchTarget).clip(CircleShape).background(ColorTokens.BrandFlame.resolve())
                        .clickable(role = Role.Button) { vm.challenge(f, m) }.padding(horizontal = SpacingTokens.M),
                    contentAlignment = Alignment.Center,
                ) { TokenText("⚡ " + stringResource(R.string.friendly_challenge), TypographyTokens.Button, color = Color.White) }
            }
        }
        AddFriendsSection(s, vm, player)
        noticeText(s)?.let { InlineBanner(it, BannerKind.Info) }
    }
}

/** Practice (no trophies): labelled bots at five levels, or a ghost run of a real player. */
@Composable
private fun PracticeSheet(vm: BattleHubViewModel, initial: BattleMode, onClose: () -> Unit) {
    var mode by rememberSaveable { mutableStateOf(initial.wire) }
    var level by rememberSaveable { mutableStateOf(BotLevel.Rookie.wire) }
    var ghost by rememberSaveable { mutableStateOf(false) }
    val m = BattleMode.of(mode) ?: BattleMode.MaxReps
    val lv = BotLevel.of(level) ?: BotLevel.Rookie
    HubSheetFrame(stringResource(R.string.practice_title), onClose) {
        Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
            Chip(stringResource(R.string.practice_bot), !ghost, Modifier.weight(1f)) { ghost = false }
            Chip(stringResource(R.string.practice_ghost), ghost, Modifier.weight(1f)) { ghost = true }
        }
        if (ghost) {
            TokenText(stringResource(R.string.battle_ghost_note), TypographyTokens.BodyS, color = ColorTokens.TextSecondary.resolve())
        } else {
            TokenText(stringResource(R.string.bot_note), TypographyTokens.BodyS, color = ColorTokens.TextSecondary.resolve())
            SectionLabel(stringResource(R.string.practice_level))
            BotLevel.entries.forEach { l ->
                val on = l == lv
                Row(
                    Modifier.fillMaxWidth().heightIn(min = MinTouchTarget).clip(RoundedCornerShape(RadiusTokens.S))
                        .background(ColorTokens.BgSurface.resolve())
                        .border(1.dp, if (on) ColorTokens.BrandLime.resolve() else Color.Transparent, RoundedCornerShape(RadiusTokens.S))
                        .selectable(on, role = Role.RadioButton) { level = l.wire }
                        .padding(horizontal = SpacingTokens.M),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    TokenText(stringResource(l.title), TypographyTokens.TitleS, Modifier.weight(1f))
                    TokenText(stringResource(l.pace), TypographyTokens.Caption, color = ColorTokens.TextSecondary.resolve())
                    TokenText(if (on) "  ●" else "  ○", TypographyTokens.TitleS,
                        color = (if (on) ColorTokens.BrandLime else ColorTokens.TextTertiary).resolve())
                }
            }
        }
        SectionLabel(stringResource(R.string.friendly_mode))
        ModeChips(QuickModes, m) { mode = it.wire }
        TokenText(modeBlurb(m), TypographyTokens.Caption, color = ColorTokens.TextSecondary.resolve())
        PrimaryButton(stringResource(if (ghost) R.string.practice_start_ghost else R.string.practice_start_bot), {
            onClose()
            if (ghost) vm.ghost(m) else vm.practice(m, lv)
        })
    }
}

/** Recent battles and past seasons. */
@Composable
private fun HistorySheet(s: BattleHubViewModel.UiState, onClose: () -> Unit) {
    HubSheetFrame(stringResource(R.string.battle_history), onClose) {
        s.arena?.record?.let { r ->
            Row(Modifier.fillMaxWidth()) {
                Stat(r.wins.toString(), stringResource(R.string.history_wins), ColorTokens.StateSuccessText, Modifier.weight(1f))
                Stat(r.losses.toString(), stringResource(R.string.history_losses), ColorTokens.StateDanger, Modifier.weight(1f))
                Stat(r.bestWinStreak.toString(), stringResource(R.string.history_best), ColorTokens.BrandFlameText, Modifier.weight(1f))
            }
        }
        SectionLabel(stringResource(R.string.history_recent))
        if (s.history.isEmpty()) {
            TokenText(stringResource(R.string.history_none), TypographyTokens.BodyS, color = ColorTokens.TextTertiary.resolve())
        }
        s.history.forEach { b ->
            Row(Modifier.fillMaxWidth().heightIn(min = MinTouchTarget).semantics(mergeDescendants = true) {},
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                val (letter, color) = when (b.winner) {
                    "me" -> "W" to ColorTokens.StateSuccessText
                    "opponent" -> "L" to ColorTokens.StateDanger
                    else -> "D" to ColorTokens.TextSecondary
                }
                TokenText(letter, TypographyTokens.TitleS, Modifier.widthIn(min = 28.dp), color = color.resolve())
                Column(Modifier.weight(1f)) {
                    TokenText(b.opponentDisplayName, TypographyTokens.BodyS)
                    TokenText(modeTitle(b.mode, b.variant), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
                }
                val t = b.myTrophies
                if (b.ranked && t != null) {
                    TokenText(if (t >= 0) "+$t 🏆" else "$t 🏆", TypographyTokens.BodyS,
                        color = (if (t >= 0) ColorTokens.StateSuccessText else ColorTokens.StateDanger).resolve())
                } else {
                    TokenText(stringResource(R.string.friendly_tag), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
                }
            }
        }
        if (s.seasons.isNotEmpty()) {
            SectionLabel(stringResource(R.string.battle_seasons))
            s.seasons.forEach { season ->
                Row(Modifier.fillMaxWidth().heightIn(min = MinTouchTarget).semantics(mergeDescendants = true) {},
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                    TokenText(leagueGlyph(season.league), TypographyTokens.TitleM, Modifier.clearAndSetSemantics {})
                    Column(Modifier.weight(1f)) {
                        TokenText(season.month, TypographyTokens.BodyS)
                        TokenText(stringResource(R.string.battle_season_line, leagueName(season.league, season.tier), season.bestTrophies),
                            TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
                    }
                    TokenText("#${season.rank}", TypographyTokens.BodyS)
                }
            }
        }
    }
}

@Composable
private fun Stat(value: String, label: String, color: TokenColor, modifier: Modifier) {
    Column(modifier.semantics(mergeDescendants = true) {}, horizontalAlignment = Alignment.CenterHorizontally) {
        TokenText(value, TypographyTokens.Stat, color = color.resolve())
        TokenText(label, TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
    }
}

@Composable
private fun ModeChips(modes: List<BattleMode>, selected: BattleMode, onSelect: (BattleMode) -> Unit) {
    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
        modes.forEach { m -> Chip(modeTitle(m.wire, m.variant), m == selected) { onSelect(m) } }
    }
}

@Composable
private fun Chip(text: String, on: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Box(
        modifier
            .heightIn(min = MinTouchTarget)
            .clip(CircleShape)
            .then(if (on) Modifier.background(heroBrush()) else Modifier.background(ColorTokens.BgSurface.resolve()))
            .selectable(on, role = Role.Tab, onClick = onClick)
            .padding(horizontal = SpacingTokens.M),
        contentAlignment = Alignment.Center,
    ) { TokenText(text, TypographyTokens.Button, color = if (on) ColorTokens.BgBase.resolve() else ColorTokens.TextPrimary.resolve()) }
}

// ------------------------------------------------------------------------------------------------ adding friends (D-072)

/**
 * Three ways to add a friend right where you challenge them (same as iOS `AddFriendsSection`): username search, share
 * your link, show your QR code — the other phone's camera opens your profile and they tap Add.
 */
@Composable
private fun AddFriendsSection(s: BattleHubViewModel.UiState, vm: BattleHubViewModel, player: BattlePlayer?) {
    val context = LocalContext.current
    var query by rememberSaveable { mutableStateOf("") }
    var showQr by remember { mutableStateOf(false) }
    val link = player?.let { "https://pushly.app/u/${it.username}" }
    SectionLabel(stringResource(R.string.friends_add))
    PushlyTextField(
        value = query,
        onValueChange = {
            query = it
            vm.searchUsers(it)
        },
        label = stringResource(R.string.friends_find),
        placeholder = stringResource(R.string.friends_find_hint),
    )
    if (query.trim().length >= 2) {
        if (s.userHits.isEmpty()) {
            TokenText(stringResource(R.string.friends_nobody), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
        }
        s.userHits.forEach { u ->
            Row(Modifier.fillMaxWidth().heightIn(min = MinTouchTarget), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Sm)) {
                Avatar(u.username, u.avatarPreset, size = 36.dp)
                TokenText(u.username, TypographyTokens.TitleS, Modifier.weight(1f), maxLines = 1)
                when (u.relation) {
                    "friends" -> Pill(stringResource(R.string.friends_already), color = ColorTokens.StateSuccessText)
                    "outgoing" -> Pill(stringResource(R.string.friends_requested))
                    "incoming" -> Pill(stringResource(R.string.friends_wants), color = ColorTokens.BrandCyan)
                    else -> Box(
                        Modifier.heightIn(min = MinTouchTarget).clip(CircleShape).background(ColorTokens.BrandFlame.resolve())
                            .clickable(role = Role.Button) { vm.addFriend(u) }.padding(horizontal = SpacingTokens.M),
                        contentAlignment = Alignment.Center,
                    ) { TokenText("+ " + stringResource(R.string.friends_add_one), TypographyTokens.Button, color = Color.White) }
                }
            }
        }
    }
    if (link != null) {
        val shareText = stringResource(R.string.friends_share_text, link)
        Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
            Chip("↗ " + stringResource(R.string.friends_share_link), false, Modifier.weight(1f)) {
                val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, shareText)
                context.startActivity(Intent.createChooser(send, null))
            }
            Chip("▦ " + stringResource(R.string.friends_my_qr), false, Modifier.weight(1f)) { showQr = true }
        }
        TokenText(stringResource(R.string.friends_qr_hint), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
        if (showQr && player != null) QrDialog(link, player.username) { showQr = false }
    }
}

/** My profile link as a big QR code on white (best for other cameras). */
@Composable
private fun QrDialog(link: String, username: String, onDismiss: () -> Unit) {
    val bitmap = remember(link) { QrCode.bitmap(link) }
    val a11y = stringResource(R.string.friends_qr_a11y, username)
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = ColorTokens.BgElevated.resolve(),
        title = { TokenText(stringResource(R.string.friends_qr_title), TypographyTokens.TitleL) },
        text = {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
                if (bitmap != null) {
                    Image(
                        bitmap.asImageBitmap(), a11y,
                        Modifier.size(240.dp).clip(RoundedCornerShape(RadiusTokens.M)).background(Color.White).padding(SpacingTokens.M),
                        filterQuality = FilterQuality.None,
                    )
                }
                TokenText("@$username", TypographyTokens.TitleM, color = ColorTokens.BrandFlameText.resolve())
                TokenText(stringResource(R.string.friends_qr_how), TypographyTokens.BodyS, color = ColorTokens.TextSecondary.resolve(),
                    textAlign = TextAlign.Center)
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { TokenText(stringResource(R.string.hub_close), TypographyTokens.Button) } },
    )
}

internal object QrCode {
    /** Black-on-white QR code (ZXing core, medium error correction, D-072). */
    fun bitmap(text: String, size: Int = 512): Bitmap? = runCatching {
        val hints = mapOf(EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.M, EncodeHintType.MARGIN to 1)
        val matrix = QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, size, size, hints)
        val pixels = IntArray(size * size) { i -> if (matrix[i % size, i / size]) android.graphics.Color.BLACK else android.graphics.Color.WHITE }
        Bitmap.createBitmap(pixels, size, size, Bitmap.Config.ARGB_8888)
    }.getOrNull()
}

// ------------------------------------------------------------------------------------------------ league ladder (D-072)

/** Every league from Bronze III to Legend: where you are, how far each step is, floors and the season end. */
@Composable
private fun LadderSheet(arena: ArenaStatus?, onClose: () -> Unit) {
    val trophies = arena?.trophies ?: 0
    val current = LeagueLadder.rungFor(trophies)
    HubSheetFrame(stringResource(R.string.ladder_title), onClose) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.M),
            modifier = Modifier.semantics(mergeDescendants = true) {}) {
            Box(Modifier.size(64.dp).clip(CircleShape).background(leagueColor(current.league).resolve().copy(alpha = 0.18f)),
                contentAlignment = Alignment.Center) { TokenText(leagueGlyph(current.league), TypographyTokens.DisplayM) }
            Column {
                TokenText(leagueName(current.league, current.tier), TypographyTokens.TitleM, color = leagueColor(current.league).resolve())
                TokenText(stringResource(R.string.ladder_trophies, trophies), TypographyTokens.BodyS)
                if (arena != null) {
                    TokenText(stringResource(R.string.ladder_best, arena.bestTrophies), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
                    arena.rank?.let { TokenText(stringResource(R.string.hub_rank, it), TypographyTokens.Caption, color = ColorTokens.BrandFlameText.resolve()) }
                }
            }
        }
        val targets = arena?.targets.orEmpty()
        if (targets.isNotEmpty()) {
            SectionLabel(stringResource(R.string.ladder_above))
            targets.forEach { t ->
                Row(Modifier.fillMaxWidth().heightIn(min = MinTouchTarget).semantics(mergeDescendants = true) {},
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Sm)) {
                    Avatar(t.username, t.avatarPreset, size = 32.dp)
                    TokenText(t.username, TypographyTokens.BodyS, Modifier.weight(1f))
                    TokenText("${t.trophies} 🏆", TypographyTokens.BodyS)
                    TokenText("+${t.gap}", TypographyTokens.Caption, color = ColorTokens.BrandFlameText.resolve())
                }
            }
        }
        SectionLabel(stringResource(R.string.ladder_all))
        LeagueLadder.rungs.asReversed().forEach { rung -> LadderRow(rung, trophies, rung == current) }
        SectionLabel(stringResource(R.string.ladder_how))
        listOf(R.string.ladder_floors, R.string.ladder_season, R.string.ladder_only_quick).forEach {
            TokenText("• " + stringResource(it), TypographyTokens.Caption, color = ColorTokens.TextSecondary.resolve())
        }
    }
}

@Composable
private fun LadderRow(rung: LeagueLadder.Rung, trophies: Int, isCurrent: Boolean) {
    val reached = rung.from <= trophies
    val color = leagueColor(rung.league).resolve()
    val shape = RoundedCornerShape(RadiusTokens.S)
    val toGo = stringResource(R.string.ladder_to_go, rung.from - trophies)
    Row(
        Modifier.fillMaxWidth().heightIn(min = MinTouchTarget).clip(shape)
            .background(if (isCurrent) color.copy(alpha = 0.14f) else ColorTokens.BgSurface.resolve())
            .padding(horizontal = SpacingTokens.M, vertical = SpacingTokens.Xs)
            .semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Sm),
    ) {
        TokenText(leagueGlyph(rung.league), TypographyTokens.TitleM, Modifier.clearAndSetSemantics {},
            color = Color.White.copy(alpha = if (reached) 1f else 0.45f))
        Column(Modifier.weight(1f)) {
            TokenText(leagueName(rung.league, rung.tier), TypographyTokens.TitleS,
                color = if (isCurrent) color else if (reached) ColorTokens.TextPrimary.resolve() else ColorTokens.TextTertiary.resolve())
            val range = if (rung.to != null) "${rung.from}–${rung.to} 🏆" else "${rung.from}+ 🏆"
            TokenText(range + if (rung.from in LeagueLadder.FLOORS) " · " + stringResource(R.string.ladder_safe_floor) else "",
                TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
            val to = rung.to
            if (isCurrent && to != null) {
                GradientProgressBar((trophies - rung.from).toFloat() / maxOf(to + 1 - rung.from, 1), Modifier.fillMaxWidth().padding(top = 2.dp), height = 6.dp)
            }
        }
        when {
            isCurrent -> Pill(stringResource(R.string.ladder_you), color = ColorTokens.BrandFlameText)
            reached -> TokenText("✓", TypographyTokens.TitleS, color = ColorTokens.StateSuccessText.resolve())
            else -> TokenText("+${rung.from - trophies}", TypographyTokens.BodyS, Modifier.semantics { contentDescription = toGo },
                color = ColorTokens.TextSecondary.resolve())
        }
    }
}

/** My Pro frame (D-074), only while Pro. */
@Composable
private fun myFrame(): String? {
    val pro = Monetization.pro.collectAsState().value
    val frame = Monetization.frame.collectAsState().value
    return if (pro) frame else null
}
