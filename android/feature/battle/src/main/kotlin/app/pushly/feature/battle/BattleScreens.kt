package app.pushly.feature.battle

import androidx.activity.compose.BackHandler
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
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
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
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import app.pushly.core.common.BattleService
import app.pushly.core.common.ReportTarget
import app.pushly.core.common.Reporter
import app.pushly.core.designsystem.ArenaBackground
import app.pushly.core.designsystem.Avatar
import app.pushly.core.designsystem.BannerKind
import app.pushly.core.designsystem.GhostButton
import app.pushly.core.designsystem.InlineBanner
import app.pushly.core.designsystem.MinTouchTarget
import app.pushly.core.designsystem.Pill
import app.pushly.core.designsystem.PrimaryButton
import app.pushly.core.designsystem.ReportAction
import app.pushly.core.designsystem.ScreenTitle
import app.pushly.core.designsystem.SecondaryButton
import app.pushly.core.designsystem.SectionLabel
import app.pushly.core.designsystem.TokenText
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.RadiusTokens
import app.pushly.core.designsystem.generated.SpacingTokens
import app.pushly.core.designsystem.generated.TokenColor
import app.pushly.core.designsystem.generated.TypographyTokens
import app.pushly.core.designsystem.resolve
import app.pushly.feature.wakeflow.RepSessionScreen
import app.pushly.feature.wakeflow.SessionServices
import java.util.Locale

@Composable
internal fun modeTitle(mode: String, variant: Map<String, Int> = emptyMap()): String = when (mode) {
    "max_reps" -> stringResource(R.string.battle_mode_max, variant["durationS"] ?: 60)
    "speed" -> stringResource(R.string.battle_mode_speed, variant["targetReps"] ?: 20)
    "endurance" -> stringResource(R.string.battle_mode_endurance)
    "best_of_3" -> stringResource(R.string.battle_mode_bo3)
    "turns" -> stringResource(R.string.battle_mode_turns)
    else -> mode
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
private fun Card(content: @Composable () -> Unit) {
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(RadiusTokens.L)).background(ColorTokens.BgSurface.resolve()).padding(SpacingTokens.M),
        verticalArrangement = Arrangement.spacedBy(SpacingTokens.S),
    ) { content() }
}

/** Battle tab (doc 07): quick match, challenges, history; a ready battle takes over the screen. */
@Composable
fun BattleHubScreen(vm: BattleHubViewModel, service: BattleService, sessions: SessionServices?, modifier: Modifier = Modifier) {
    val s by vm.state.collectAsStateWithLifecycle()
    LaunchedEffect(vm) { vm.load() }
    val active = s.active
    if (active != null) {
        val live = viewModel(key = "battle-${active.id}") { LiveBattleViewModel(active, service, sessions) }
        LiveBattleScreen(live, onClose = vm::closeBattle, onRematch = vm::rematch)
        return
    }
    var mode by remember { mutableStateOf(BattleMode.MaxReps) }
    var ranked by remember { mutableStateOf(false) }
    var botLevel by remember { mutableStateOf(BotLevel.Rookie) }
    ArenaBackground(modifier, glow = ColorTokens.BrandVolt, glowOffset = DpOffset(0.dp, (-260).dp)) {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(SpacingTokens.L),
            verticalArrangement = Arrangement.spacedBy(SpacingTokens.M),
        ) {
            ScreenTitle(stringResource(R.string.battle_title), token = TypographyTokens.DisplayM)
            TokenText(stringResource(R.string.battle_pitch), TypographyTokens.Body, color = ColorTokens.TextSecondary.resolve())
            when (s.notice) {
                BattleHubViewModel.Notice.QueueFailed -> InlineBanner(stringResource(R.string.battle_queue_failed), BannerKind.Warning)
                BattleHubViewModel.Notice.NobodyFound -> InlineBanner(stringResource(R.string.battle_nobody), BannerKind.Info)
                BattleHubViewModel.Notice.ChallengeSent -> InlineBanner(stringResource(R.string.battle_challenge_sent, s.noticeName), BannerKind.Info)
                BattleHubViewModel.Notice.ChallengeFailed -> InlineBanner(stringResource(R.string.battle_challenge_failed), BannerKind.Warning)
                BattleHubViewModel.Notice.Expired -> InlineBanner(stringResource(R.string.battle_expired), BannerKind.Info)
                BattleHubViewModel.Notice.GhostLimit -> InlineBanner(stringResource(R.string.battle_ghost_limit), BannerKind.Info)
                BattleHubViewModel.Notice.NoGhost -> InlineBanner(stringResource(R.string.battle_no_ghost), BannerKind.Info)
                BattleHubViewModel.Notice.BotFailed -> InlineBanner(stringResource(R.string.bot_failed), BannerKind.Warning)
                BattleHubViewModel.Notice.None -> Unit
            }
            if (s.botOffer != null && s.queuedMode == null) {
                PrimaryButton(stringResource(R.string.bot_instead), vm::practiceInsteadOfWaiting)
            }

            SectionLabel(stringResource(R.string.battle_quick))
            Card {
                val queued = s.queuedMode
                if (queued != null) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                        CircularProgressIndicator(Modifier.widthIn(max = 24.dp), color = ColorTokens.BrandFlame.resolve())
                        TokenText(stringResource(R.string.battle_finding, modeTitle(queued.wire, queued.variant), s.waitedS),
                            TypographyTokens.BodyS, modifier = Modifier.weight(1f))
                        SmallButton(stringResource(R.string.battle_cancel), ColorTokens.TextSecondary, vm::cancelQueue)
                    }
                    if (s.waitedS >= 15) {
                        SmallButton(stringResource(R.string.bot_nobody_yet), ColorTokens.BrandCyan, vm::practiceInsteadOfWaiting)
                    }
                } else {
                    BattleMode.entries.filter { it.quickMatch }.forEach { m ->
                        PrimaryButton(modeTitle(m.wire, m.variant), { vm.quickMatch(m) })
                    }
                }
            }

            SectionLabel(stringResource(R.string.battle_ghost))
            Card {
                BattleMode.entries.filter { it.quickMatch }.forEach { m ->
                    SmallButton(modeTitle(m.wire, m.variant), ColorTokens.BrandCyan) { vm.ghost(m) }
                }
                TokenText(stringResource(R.string.battle_ghost_note), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
            }

            SectionLabel(stringResource(R.string.bot_section))
            Card {
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                    BotLevel.entries.forEach { level ->
                        val on = level == botLevel
                        Box(
                            Modifier
                                .heightIn(min = MinTouchTarget)
                                .clip(CircleShape)
                                .background(if (on) ColorTokens.BgElevated.resolve() else ColorTokens.BgSurface.resolve())
                                .border(1.dp, if (on) ColorTokens.BrandCyan.resolve() else ColorTokens.StrokeSubtle.resolve(), CircleShape)
                                .selectable(on, role = Role.Tab) { botLevel = level }
                                .padding(horizontal = SpacingTokens.Sm),
                            contentAlignment = Alignment.Center,
                        ) { TokenText(stringResource(level.title), TypographyTokens.Caption) }
                    }
                }
                TokenText(stringResource(botLevel.pace), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
                BattleMode.entries.filter { it.quickMatch }.forEach { m ->
                    SmallButton("🤖 " + modeTitle(m.wire, m.variant), ColorTokens.BrandCyan) { vm.practice(m, botLevel) }
                }
                TokenText(stringResource(R.string.bot_note), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
            }

            if (s.invites.incoming.isNotEmpty()) {
                SectionLabel(stringResource(R.string.battle_for_you))
                Card {
                    s.invites.incoming.forEach { inv ->
                        Row(Modifier.fillMaxWidth().heightIn(min = MinTouchTarget), verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                            Avatar(inv.from.username, inv.from.avatarPreset, size = 36.dp)
                            Column(Modifier.weight(1f)) {
                                TokenText(inv.from.username, TypographyTokens.TitleS)
                                TokenText(modeTitle(inv.mode, inv.variant) + if (inv.ranked) " · " + stringResource(R.string.battle_ranked_short) else "",
                                    TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
                            }
                            SmallButton(stringResource(R.string.battle_fight)) { vm.accept(inv) }
                            SmallButton(stringResource(R.string.battle_no), ColorTokens.TextSecondary) { vm.decline(inv) }
                        }
                    }
                }
            }

            SectionLabel(stringResource(R.string.battle_challenge))
            Card {
                Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                    BattleMode.entries.forEach { m ->
                        val on = m == mode
                        Box(
                            Modifier
                                .heightIn(min = MinTouchTarget)
                                .clip(CircleShape)
                                .background(if (on) ColorTokens.BgElevated.resolve() else ColorTokens.BgSurface.resolve())
                                .border(1.dp, if (on) ColorTokens.BrandFlame.resolve() else ColorTokens.StrokeSubtle.resolve(), CircleShape)
                                .selectable(on, role = Role.Tab) { mode = m }
                                .padding(horizontal = SpacingTokens.Sm),
                            contentAlignment = Alignment.Center,
                        ) { TokenText(modeTitle(m.wire, m.variant), TypographyTokens.Caption) }
                    }
                }
                Row(
                    Modifier.fillMaxWidth().heightIn(min = MinTouchTarget).toggleable(ranked, role = Role.Switch) { ranked = it },
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(stringResource(R.string.battle_ranked_toggle), modifier = Modifier.weight(1f))
                    Switch(ranked, onCheckedChange = null, colors = SwitchDefaults.colors(checkedTrackColor = ColorTokens.BrandFlame.resolve()))
                }
                if (s.friends.isEmpty()) {
                    TokenText(stringResource(R.string.battle_no_friends), TypographyTokens.BodyS, color = ColorTokens.TextTertiary.resolve())
                }
                s.friends.forEach { f ->
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = MinTouchTarget).clickable(role = Role.Button) { vm.challenge(f, mode, ranked) },
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S),
                    ) {
                        Avatar(f.username, f.avatarPreset, size = 32.dp)
                        TokenText(f.username, TypographyTokens.Body, modifier = Modifier.weight(1f))
                        TokenText("⚡", TypographyTokens.Body)
                    }
                }
            }

            if (s.seasons.isNotEmpty()) {
                SectionLabel(stringResource(R.string.battle_seasons))
                Card {
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

            if (s.history.isNotEmpty()) {
                SectionLabel(stringResource(R.string.battle_history))
                Card {
                    s.history.forEach { b ->
                        Row(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                            val (letter, color) = when (b.winner) {
                                "me" -> "W" to ColorTokens.StateSuccessText
                                "opponent" -> "L" to ColorTokens.StateDanger
                                else -> "D" to ColorTokens.TextSecondary
                            }
                            TokenText(letter, TypographyTokens.TitleS, color = color.resolve(), modifier = Modifier.widthIn(min = 28.dp))
                            Column(Modifier.weight(1f)) {
                                TokenText(b.opponentDisplayName, TypographyTokens.BodyS)
                                TokenText(modeTitle(b.mode, b.variant), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
                            }
                            val t = b.myTrophies
                            if (b.ranked && t != null) TokenText(if (t >= 0) "+$t 🏆" else "$t 🏆", TypographyTokens.BodyS)
                        }
                    }
                }
            }
        }
    }
}

/** Live battle (doc 07 §6): camera + my counter, opponent score, timer; then the result. */
@Composable
fun LiveBattleScreen(vm: LiveBattleViewModel, onClose: () -> Unit, onRematch: ((Battle) -> Unit)? = null) {
    val s by vm.state.collectAsStateWithLifecycle()
    LaunchedEffect(vm) { vm.start() }
    BackHandler { if (s.phase is LiveBattleViewModel.Phase.Done || s.phase is LiveBattleViewModel.Phase.Cancelled) onClose() else vm.leave() }
    when (s.phase) {
        LiveBattleViewModel.Phase.Waiting, LiveBattleViewModel.Phase.Done, LiveBattleViewModel.Phase.Cancelled -> BattleResult(s, onClose, onRematch)
        else -> RepSessionScreen(vm.reps) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.semantics(mergeDescendants = true) {}) {
                    TokenText(s.battle.opponentDisplayName, TypographyTokens.Caption)
                    TokenText("${s.battle.theirScore}", TypographyTokens.Stat, color = ColorTokens.BrandVoltText.resolve())
                }
                Spacer(Modifier.weight(1f))
                val phase = s.phase
                TokenText(
                    when (phase) {
                        LiveBattleViewModel.Phase.Lobby -> stringResource(R.string.battle_get_ready)
                        is LiveBattleViewModel.Phase.Countdown -> "${phase.seconds}"
                        LiveBattleViewModel.Phase.Live -> s.secondsLeft?.let { "$it s" } ?: stringResource(R.string.battle_go)
                        else -> ""
                    },
                    TypographyTokens.TitleM,
                )
                Spacer(Modifier.weight(1f))
                GhostButton(stringResource(R.string.battle_leave), vm::leave)
            }
            if (s.phase == LiveBattleViewModel.Phase.Live) ModeHud(vm, s)
        }
    }
}

/** Mode-specific HUD line (doc 07 §6): round dots + set/rest for Best of 3, whose turn + 5 s window for Turns. */
@Composable
private fun ModeHud(vm: LiveBattleViewModel, s: LiveBattleViewModel.UiState) {
    val t = s.elapsedMs ?: return
    when (s.battle.mode) {
        "best_of_3" -> {
            val clock = BattleHud.bo3Clock(t)
            val mine = BattleHud.mySets(vm.myRepsSnapshot())
            val theirs = s.battle.theirRounds
            val secs = ((clock.msLeft + 999) / 1000).toInt()
            val text = when {
                clock.phase == "rest" -> stringResource(R.string.battle_bo3_rest, clock.round + 2, secs)
                clock.phase == "set" && vm.bo3SetOver -> stringResource(R.string.battle_bo3_set_over)
                clock.phase == "set" -> stringResource(R.string.battle_bo3_round, clock.round + 1, secs)
                else -> ""
            }
            Column(
                Modifier.fillMaxWidth().semantics(mergeDescendants = true) {},
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(SpacingTokens.Xs),
            ) {
                Row(Modifier.clearAndSetSemantics {}, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                    for (r in 0..2) {
                        val done = r < clock.round || (clock.phase == "rest" && r == clock.round) || clock.phase == "over"
                        val my = mine.getOrElse(r) { 0 }
                        val their = theirs.getOrElse(r) { 0 }
                        val color = when {
                            !done -> ColorTokens.StrokeStrong
                            my > their -> ColorTokens.StateSuccess
                            my < their -> ColorTokens.StateDanger
                            else -> ColorTokens.TextTertiary
                        }
                        Box(
                            Modifier.size(12.dp).clip(CircleShape).background(color.resolve())
                                .border(if (r == clock.round && !done) 2.dp else 0.dp, ColorTokens.TextPrimary.resolve(), CircleShape),
                        )
                    }
                }
                TokenText(text, TypographyTokens.LabelDisplay,
                    color = (if (clock.phase == "rest") ColorTokens.BrandCyan else ColorTokens.TextPrimary).resolve())
            }
        }
        "turns" -> {
            val state = vm.turn(t)
            val left = maxOf(0.0, (state?.msLeft ?: 0L) / 1000.0)
            val text = when (state?.turn) {
                "me" -> stringResource(R.string.battle_turn_mine, String.format(Locale.US, "%.1f", left))
                "them" -> stringResource(R.string.battle_turn_theirs)
                else -> stringResource(R.string.battle_turn_anyone)
            }
            Row(
                Modifier.fillMaxWidth().semantics(mergeDescendants = true) {},
                horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S, Alignment.CenterHorizontally),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (state?.turn == "me") {
                    LinearProgressIndicator(
                        progress = { (left / 5.0).toFloat().coerceIn(0f, 1f) },
                        modifier = Modifier.width(80.dp).clearAndSetSemantics {},
                        color = (if (left < 2) ColorTokens.StateDanger else ColorTokens.BrandFlame).resolve(),
                    )
                }
                TokenText(text, TypographyTokens.LabelDisplay,
                    color = (if (state?.turn == "me") ColorTokens.BrandFlameText else ColorTokens.TextSecondary).resolve())
            }
        }
    }
}

@Composable
private fun BattleResult(s: LiveBattleViewModel.UiState, onClose: () -> Unit, onRematch: ((Battle) -> Unit)?) {
    val settled = s.battle.status == "settled"
    val won = s.battle.winner == "me"
    val lost = s.battle.winner == "opponent"
    val r = s.battle.result
    val mine = if (r != null) (if (s.battle.me == "a") r.a.reps else r.b.reps) else s.myCount
    val theirs = if (r != null) (if (s.battle.me == "a") r.b.reps else r.a.reps) else s.battle.theirScore
    ArenaBackground(glow = if (won) ColorTokens.LeagueGold else ColorTokens.BrandVolt) {
        Column(Modifier.fillMaxSize().safeDrawingPadding().padding(SpacingTokens.L), verticalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
            Spacer(Modifier.weight(1f))
            if (s.phase == LiveBattleViewModel.Phase.Cancelled) {
                SectionLabel(stringResource(R.string.battle_cancelled))
                TokenText(stringResource(R.string.battle_cancelled_text), TypographyTokens.Body)
            } else {
                SectionLabel(
                    stringResource(
                        when {
                            !settled -> R.string.battle_checking
                            won -> R.string.battle_victory
                            lost -> R.string.battle_defeat
                            else -> R.string.battle_draw
                        },
                    ),
                    color = if (won) ColorTokens.StateSuccessText else ColorTokens.TextSecondary,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.L), verticalAlignment = Alignment.Bottom) {
                    Column {
                        TokenText(stringResource(R.string.battle_you), TypographyTokens.Caption)
                        TokenText("$mine", TypographyTokens.DisplayCounter)
                    }
                    Column {
                        TokenText(s.battle.opponentDisplayName, TypographyTokens.Caption)
                        TokenText("$theirs", TypographyTokens.DisplayL, color = ColorTokens.TextSecondary.resolve())
                    }
                }
                val ra = r?.a?.rounds
                val rb = r?.b?.rounds
                if (settled && ra != null && rb != null) {
                    val (mr, tr) = if (s.battle.me == "a") ra to rb else rb to ra
                    TokenText(stringResource(R.string.battle_rounds_result, mr, tr), TypographyTokens.TitleM)
                }
                if (settled && r?.reason == "turn_missed") {
                    TokenText(stringResource(if (won) R.string.battle_they_missed else R.string.battle_you_missed), TypographyTokens.Body,
                        color = ColorTokens.TextSecondary.resolve())
                }
                val t = s.battle.myTrophies
                if (settled && s.battle.ranked && t != null) {
                    Pill(stringResource(R.string.battle_trophies, if (t >= 0) "+$t" else "$t"),
                        color = if (t >= 0) ColorTokens.LeagueGold else ColorTokens.StateDanger)
                } else if (!settled) {
                    CircularProgressIndicator(color = ColorTokens.BrandFlame.resolve())
                }
            }
            Spacer(Modifier.weight(1f))
            if (settled && s.battle.ghost != true && Reporter.isAvailable) {
                ReportAction(stringResource(R.string.battle_report)) { reason -> Reporter.send(ReportTarget.Battle(s.battle.id), reason) }
            }
            val canRematch = (s.battle.type in setOf("friendly", "friend_ranked") && s.battle.opponent.id != null) || s.battle.bot != null
            if (settled && onRematch != null && canRematch) {
                SecondaryButton(stringResource(R.string.battle_rematch), { onRematch(s.battle) })
            }
            PrimaryButton(stringResource(R.string.battle_done), onClose)
        }
    }
}

@Composable
private fun leagueName(league: String, tier: String?): String {
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
