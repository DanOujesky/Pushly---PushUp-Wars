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
import androidx.compose.foundation.layout.height
import app.pushly.feature.wakeflow.RepSounds
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.pushly.core.common.ReportTarget
import app.pushly.core.common.Reporter
import app.pushly.core.designsystem.ArenaBackground
import app.pushly.core.designsystem.GhostButton
import app.pushly.core.designsystem.MinTouchTarget
import app.pushly.core.designsystem.Pill
import app.pushly.core.designsystem.PrimaryButton
import app.pushly.core.designsystem.ReportAction
import app.pushly.core.designsystem.SideViewNotice
import app.pushly.core.designsystem.SecondaryButton
import app.pushly.core.designsystem.SectionLabel
import app.pushly.core.designsystem.TokenText
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.RadiusTokens
import app.pushly.core.designsystem.generated.SpacingTokens
import app.pushly.core.designsystem.generated.TypographyTokens
import app.pushly.core.designsystem.resolve
import app.pushly.feature.wakeflow.RepSessionScreen
import java.util.Locale
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.key
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.viewinterop.AndroidView
import io.livekit.android.renderer.TextureViewRenderer
import io.livekit.android.room.track.VideoTrack
import kotlinx.coroutines.launch

@Composable
internal fun modeTitle(mode: String, variant: Map<String, Int> = emptyMap()): String = when (mode) {
    "max_reps" -> stringResource(R.string.battle_mode_max, variant["durationS"] ?: 60)
    "speed" -> stringResource(R.string.battle_mode_speed, variant["targetReps"] ?: 20)
    "endurance" -> stringResource(R.string.battle_mode_endurance)
    "best_of_3" -> stringResource(R.string.battle_mode_bo3)
    "turns" -> stringResource(R.string.battle_mode_turns)
    else -> mode
}

/** Live battle (doc 07 §6): camera + my counter, opponent score, timer; then the result. */
@Composable
fun LiveBattleScreen(vm: LiveBattleViewModel, onClose: () -> Unit, onRematch: ((Battle) -> Unit)? = null) {
    val s by vm.state.collectAsStateWithLifecycle()
    LaunchedEffect(vm) { vm.start() }
    BackHandler { if (s.phase is LiveBattleViewModel.Phase.Done || s.phase is LiveBattleViewModel.Phase.Cancelled) onClose() else vm.leave() }
    val context = LocalContext.current
    val video = remember(vm) { BattleVideo(context.applicationContext) }
    DisposableEffect(vm) {
        vm.startVideo(video)
        onDispose { video.stop() }
    }
    val remote by video.remoteTrack.collectAsStateWithLifecycle()
    val videoState by video.state.collectAsStateWithLifecycle()
    val cameraOn by video.cameraOn.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    val sounds = remember { RepSounds(context) }
    DisposableEffect(Unit) { onDispose { sounds.release() } }
    var flash by remember { mutableStateOf<Pair<String, Boolean>?>(null) }
    var flashId by remember { mutableStateOf(0) }
    LaunchedEffect(vm) {
        vm.callouts.collect { c ->
            when (c) {
                is BattleCallout.Countdown -> sounds.play(RepSounds.Effect.Count)
                BattleCallout.Go -> sounds.play(RepSounds.Effect.Go)
                BattleCallout.OpponentRep -> sounds.play(RepSounds.Effect.Opponent)
                BattleCallout.TookLead -> sounds.play(RepSounds.Effect.Lead)
                BattleCallout.LostLead, is BattleCallout.Behind -> sounds.play(RepSounds.Effect.Behind)
                else -> Unit
            }
            val text = calloutText(context, c) ?: return@collect
            sounds.announce(text)
            if (c !is BattleCallout.Countdown) {
                flash = text to (c !is BattleCallout.LostLead && c !is BattleCallout.Behind)
                val id = ++flashId
                scope.launch {
                    kotlinx.coroutines.delay(1400)
                    if (flashId == id) flash = null
                }
            }
        }
    }
    Box(Modifier.fillMaxSize()) {
    when (s.phase) {
        LiveBattleViewModel.Phase.Waiting, LiveBattleViewModel.Phase.Done, LiveBattleViewModel.Phase.Cancelled -> BattleResult(s, onClose, onRematch)
        else -> Column(Modifier.fillMaxSize().background(Color.Black)) {
            remote?.let { track ->
                key(track) {
                    OpponentVideo(track, video, s.battle.opponentDisplayName, s.battle.theirScore, Modifier.fillMaxWidth().fillMaxHeight(0.42f))
                }
            }
            Box(Modifier.weight(1f)) { LiveSession(vm, s, videoState == BattleVideo.State.Connected, cameraOn) { scope.launch { video.toggleCamera() } } }
        }
    }
    flash?.let { (text, positive) ->
        Box(Modifier.fillMaxSize().clearAndSetSemantics {}, contentAlignment = Alignment.Center) {
            TokenText(
                text.uppercase(Locale.ROOT),
                TypographyTokens.DisplayM,
                color = (if (positive) ColorTokens.StateSuccess else ColorTokens.StateDanger).resolve(),
                modifier = Modifier.padding(SpacingTokens.L),
            )
        }
    }
    }
}

/** The opponent's camera (top half, doc 07 §6) with their name and live score. */
@Composable
private fun OpponentVideo(track: VideoTrack, video: BattleVideo, name: String, score: Int, modifier: Modifier) {
    val label = stringResource(R.string.battle_opponent_camera, name)
    Box(modifier.semantics { contentDescription = label }) {
        AndroidView(
            factory = { ctx ->
                TextureViewRenderer(ctx).also { r ->
                    video.room?.initVideoRenderer(r)
                    track.addRenderer(r)
                }
            },
            onRelease = { r ->
                track.removeRenderer(r)
                r.release()
            },
            modifier = Modifier.fillMaxSize(),
        )
        Row(
            Modifier.align(Alignment.BottomStart).fillMaxWidth()
                .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.6f))))
                .padding(SpacingTokens.M),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TokenText(name, TypographyTokens.LabelDisplay, color = Color.White, modifier = Modifier.weight(1f))
            TokenText("$score", TypographyTokens.Stat, color = ColorTokens.BrandVoltText.resolve())
        }
    }
}

@Composable
private fun LiveSession(
    vm: LiveBattleViewModel,
    s: LiveBattleViewModel.UiState,
    videoConnected: Boolean,
    cameraOn: Boolean,
    onToggleCamera: () -> Unit,
) {
    RepSessionScreen(vm.reps) {
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
                if (videoConnected) {
                    val camLabel = stringResource(if (cameraOn) R.string.battle_camera_stop else R.string.battle_camera_share)
                    Box(
                        Modifier.size(MinTouchTarget).clickable(role = Role.Switch, onClick = onToggleCamera)
                            .semantics { contentDescription = camLabel },
                        contentAlignment = Alignment.Center,
                    ) { TokenText(if (cameraOn) "📹" else "🚫", TypographyTokens.TitleM) }
                }
                GhostButton(stringResource(R.string.battle_leave), vm::leave)
            }
            val lead = s.lead
            if (s.phase == LiveBattleViewModel.Phase.Live && lead != null) LeadBar(lead.first, lead.second, s.battle.opponentDisplayName)
            if (s.phase == LiveBattleViewModel.Phase.Live) {
                ModeHud(vm, s)
            } else {
                SideViewNotice(
                    Modifier.clip(RoundedCornerShape(RadiusTokens.S)).background(Color.Black.copy(alpha = 0.5f)).padding(SpacingTokens.S),
                    compact = true,
                )
            }
    }
}

private fun calloutText(context: android.content.Context, c: BattleCallout): String? = when (c) {
    is BattleCallout.Countdown -> "${c.seconds}"
    BattleCallout.Go -> context.getString(R.string.callout_go)
    BattleCallout.OpponentRep -> null
    BattleCallout.TookLead -> context.getString(R.string.callout_lead)
    BattleCallout.LostLead -> context.getString(R.string.callout_lost_lead)
    BattleCallout.Tied -> context.getString(R.string.callout_tied)
    is BattleCallout.Behind -> context.getString(R.string.callout_behind, c.reps)
    is BattleCallout.SecondsLeft -> context.getString(if (c.seconds >= 30) R.string.callout_30s else R.string.callout_10s)
}

/** Tug of war (D-066): who leads and by how much, at a glance — my share of the reps fills from the left. */
@Composable
private fun LeadBar(mine: Int, theirs: Int, opponent: String) {
    val diff = mine - theirs
    val total = mine + theirs
    val share by androidx.compose.animation.core.animateFloatAsState(if (total == 0) 0.5f else mine / total.toFloat(), label = "lead")
    val a11y = when {
        diff > 0 -> stringResource(R.string.lead_a11y_ahead, diff)
        diff < 0 -> stringResource(R.string.lead_a11y_behind, -diff)
        else -> stringResource(R.string.lead_a11y_level)
    }
    Column(Modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = a11y }, horizontalAlignment = Alignment.CenterHorizontally) {
        TokenText(
            if (diff > 0) "+$diff" else if (diff < 0) "−${-diff}" else "=",
            TypographyTokens.DisplayM,
            color = (if (diff > 0) ColorTokens.StateSuccess else if (diff < 0) ColorTokens.StateDanger else ColorTokens.TextPrimary).resolve(),
        )
        Box(Modifier.fillMaxWidth().height(14.dp).clip(CircleShape).background(ColorTokens.BrandVolt.resolve())) {
            Box(Modifier.fillMaxWidth(share.coerceIn(0.03f, 1f)).fillMaxHeight().clip(CircleShape).background(ColorTokens.BrandFlame.resolve()))
            Box(Modifier.align(Alignment.Center).width(2.dp).fillMaxHeight().background(Color.White.copy(alpha = 0.9f)))
        }
        Row(Modifier.fillMaxWidth()) {
            TokenText(stringResource(R.string.lead_you, mine), TypographyTokens.Caption, color = Color.White.copy(alpha = 0.85f), modifier = Modifier.weight(1f))
            TokenText("$theirs $opponent", TypographyTokens.Caption, color = Color.White.copy(alpha = 0.85f))
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
internal fun leagueName(league: String, tier: String?): String {
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
