package app.pushly.feature.alarm

import androidx.compose.foundation.background
import app.pushly.core.designsystem.generated.RadiusTokens
import app.pushly.core.designsystem.generated.TokenColor
import app.pushly.core.designsystem.MinTouchTarget
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.Color
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.Canvas
import app.pushly.core.alarm.WakeSummary
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import app.pushly.core.alarm.AlarmSchedule
import app.pushly.core.alarm.HealthIssue
import app.pushly.core.alarm.HealthSeverity
import app.pushly.core.designsystem.ArenaBackground
import app.pushly.core.designsystem.BannerKind
import app.pushly.core.designsystem.GhostButton
import app.pushly.core.designsystem.GlowSpot
import app.pushly.core.designsystem.InlineBanner
import app.pushly.core.designsystem.PrimaryButton
import app.pushly.core.designsystem.ScreenTitle
import app.pushly.core.designsystem.TokenText
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.SpacingTokens
import app.pushly.core.designsystem.generated.TypographyTokens
import app.pushly.core.designsystem.resolve
import kotlinx.coroutines.delay
import java.time.Duration
import java.time.ZoneId

private sealed interface WakeRoute {
    data object List : WakeRoute
    data class Edit(val schedule: AlarmSchedule, val isNew: Boolean) : WakeRoute
    data object Permissions : WakeRoute
}

/** Debug builds only: route the Wake tab opens on (set by the app's debug screen launcher). */
object WakeDebug {
    @Volatile var initialRoute: String? = null
}

/** The Wake tab (doc 02 PS-20…26): next alarm, health warnings, alarm list, editor and permission explainer. */
@Composable
fun WakeTab(modifier: Modifier = Modifier, vm: WakeViewModel = viewModel()) {
    var route by remember {
        mutableStateOf<WakeRoute>(
            when (WakeDebug.initialRoute.also { WakeDebug.initialRoute = null }) {
                "editor" -> vm.state.value.items.firstOrNull()?.let { WakeRoute.Edit(it.schedule, isNew = false) }
                    ?: WakeRoute.Edit(vm.newSchedule(), isNew = true)
                "permissions" -> WakeRoute.Permissions
                else -> WakeRoute.List
            },
        )
    }
    LifecycleResumeEffect(Unit) {
        vm.refresh()
        onPauseOrDispose { }
    }
    when (val r = route) {
        WakeRoute.List -> WakeHome(
            vm = vm,
            modifier = modifier,
            onNew = { route = WakeRoute.Edit(vm.newSchedule(), isNew = true) },
            onEdit = { route = WakeRoute.Edit(it, isNew = false) },
            onFixPermissions = { route = WakeRoute.Permissions },
        )
        is WakeRoute.Edit -> AlarmEditor(
            initial = r.schedule,
            isNew = r.isNew,
            vm = vm,
            modifier = modifier,
            onDone = { saved ->
                route = if (saved && vm.missingPermissions().isNotEmpty()) WakeRoute.Permissions else WakeRoute.List
            },
        )
        WakeRoute.Permissions -> PermissionsScreen(modifier = modifier, onDone = {
            vm.refresh()
            route = WakeRoute.List
        })
    }
}

@Composable
private fun WakeHome(
    vm: WakeViewModel,
    modifier: Modifier,
    onNew: () -> Unit,
    onEdit: (AlarmSchedule) -> Unit,
    onFixPermissions: () -> Unit,
) {
    val s by vm.state.collectAsStateWithLifecycle()
    val health by vm.health.collectAsStateWithLifecycle()
    val notice by vm.notice.collectAsStateWithLifecycle()
    val summary by vm.summary.collectAsStateWithLifecycle()
    val pending by vm.pendingSessions.collectAsStateWithLifecycle()
    val context = LocalContext.current
    LaunchedEffect(notice) {
        if (notice != null) {
            delay(6_000)
            vm.clearNotice()
        }
    }
    ArenaBackground(modifier, glow = ColorTokens.BrandFlame, glowOffset = DpOffset(160.dp, (-240).dp)) {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = SpacingTokens.Ml, vertical = SpacingTokens.L),
            verticalArrangement = Arrangement.spacedBy(SpacingTokens.L),
        ) {
            WakeHeader(summary?.streak?.current)

            if (health.isNotEmpty() || notice != null) {
                Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                    health.forEach { issue -> HealthCard(issue, onFix = {
                        if (issue in setOf(HealthIssue.ExactAlarmMissing, HealthIssue.FullScreenIntentMissing, HealthIssue.NotificationsBlocked)) {
                            onFixPermissions()
                        } else {
                            runCatching { context.startActivity(AlarmPermissions.intentFor(context, issue)) }
                        }
                    }) }
                    notice?.let { InlineBanner(stringResource(it), BannerKind.Info) }
                }
            }

            NextAlarmCard(s, onNew)

            summary?.let { sum ->
                WakeStatsRow(sum)
                WeekCard(sum)
            }
            if (pending.isNotEmpty()) {
                TokenText(stringResource(R.string.wake_pending, pending.size), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
            }

            if (s.items.isNotEmpty()) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        TokenText(stringResource(R.string.wake_alarms), TypographyTokens.TitleL)
                        TokenText(
                            stringResource(R.string.wake_alarm_count, s.items.size, AlarmSchedule.MAX_ALARMS_PER_USER),
                            TypographyTokens.Caption,
                            color = ColorTokens.TextTertiary.resolve(),
                        )
                    }
                    if (vm.canAddAlarm()) {
                        val label = stringResource(R.string.wake_new_alarm)
                        Box(
                            Modifier.size(MinTouchTarget).clip(CircleShape).background(heroGradient())
                                .clickable(role = Role.Button, onClick = onNew).semantics { contentDescription = label },
                            contentAlignment = Alignment.Center,
                        ) { TokenText("+", TypographyTokens.TitleL, color = ColorTokens.BgBase.resolve()) }
                    }
                }
                s.items.forEach { item ->
                    AlarmCard(
                        item = item,
                        now = s.now,
                        onClick = { onEdit(item.schedule) },
                        onToggle = { vm.setEnabled(item.schedule.id, it) },
                        onSkip = { vm.skipNext(item.schedule.id) },
                        onUndoSkip = { date -> vm.undoSkip(item.schedule.id, date) },
                    )
                }
            }
            Spacer(Modifier.padding(bottom = SpacingTokens.L))
        }
    }
}

@Composable
private fun HealthCard(issue: HealthIssue, onFix: () -> Unit) {
    val text = stringResource(healthText(issue))
    Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
        InlineBanner(text, if (issue.severity == HealthSeverity.Critical) BannerKind.Error else BannerKind.Warning)
        if (issue != HealthIssue.CustomSoundMissing) {
            GhostButton(stringResource(R.string.wake_fix), onClick = onFix, modifier = Modifier.align(Alignment.End))
        }
    }
}

private fun healthText(issue: HealthIssue): Int = when (issue) {
    HealthIssue.AlarmKitNotAuthorized -> R.string.health_alarmKitNotAuthorized
    HealthIssue.ExactAlarmMissing -> R.string.health_exactAlarmMissing
    HealthIssue.FullScreenIntentMissing -> R.string.health_fullScreenIntentMissing
    HealthIssue.NotificationsBlocked -> R.string.health_notificationsBlocked
    HealthIssue.AlarmChannelMuted -> R.string.health_alarmChannelMuted
    HealthIssue.CameraDenied -> R.string.health_cameraDenied
    HealthIssue.NextAlarmNotArmed -> R.string.health_nextAlarmNotArmed
    HealthIssue.BatteryRestricted -> R.string.health_batteryRestricted
    HealthIssue.AlarmVolumeZero -> R.string.health_alarmVolumeZero
    HealthIssue.CustomSoundMissing -> R.string.health_customSoundMissing
}

@Composable
private fun heroGradient(): Brush = Brush.linearGradient(listOf(ColorTokens.BrandFlame.resolve(), ColorTokens.BrandVolt.resolve()))

/** "Good morning" + Wake title, streak pill on the right. */
@Composable
private fun WakeHeader(streak: Int?) {
    val greeting = stringResource(
        when (WakeTabRules.greetingBucket(java.time.LocalTime.now().hour)) {
            "morning" -> R.string.wake_greeting_morning
            "afternoon" -> R.string.wake_greeting_afternoon
            "evening" -> R.string.wake_greeting_evening
            else -> R.string.wake_greeting_night
        },
    )
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            TokenText(greeting, TypographyTokens.BodyS, color = ColorTokens.TextSecondary.resolve())
            ScreenTitle(stringResource(R.string.wake_title), token = TypographyTokens.DisplayM)
        }
        streak?.let { StreakBadge(it) }
    }
}

/** The hero: next alarm time, a ring counting down the last 24 hours, the challenge it carries. Same as iOS. */
@Composable
private fun NextAlarmCard(s: WakeViewModel.State, onNew: () -> Unit) {
    val context = LocalContext.current
    val shape = RoundedCornerShape(28.dp)
    val next = s.next
    Box(
        Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Brush.linearGradient(listOf(ColorTokens.BgSurface.resolve(), ColorTokens.BgElevated.resolve())))
            .border(1.dp, ColorTokens.StrokeSubtle.resolve(), shape),
    ) {
        GlowSpot(ColorTokens.BrandFlame, size = 300.dp, intensity = 0.35f, modifier = Modifier.align(Alignment.TopEnd).padding(start = 120.dp))
        Column(Modifier.padding(SpacingTokens.L), verticalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
            if (next == null) {
                Box(Modifier.size(72.dp).clip(CircleShape).background(ColorTokens.BrandFlame.resolve().copy(alpha = 0.16f)),
                    contentAlignment = Alignment.Center) {
                    TokenText("⏰", TypographyTokens.DisplayM, Modifier.clearAndSetSemantics {})
                }
                TokenText(stringResource(R.string.wake_no_alarm_title), TypographyTokens.DisplayM)
                TokenText(stringResource(R.string.wake_no_alarm_text), TypographyTokens.Body, color = ColorTokens.TextSecondary.resolve())
                PrimaryButton(stringResource(R.string.wake_set_alarm), onNew)
            } else {
                val local = next.instant.atZone(ZoneId.systemDefault())
                val schedule = s.items.firstOrNull { it.schedule.id == next.alarmId }?.schedule
                val left = Duration.between(s.now, next.instant)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.L)) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
                        TokenText(
                            stringResource(R.string.wake_next_alarm, TimeFormat.dayShort(local.dayOfWeek)).uppercase(),
                            TypographyTokens.Overline,
                            color = ColorTokens.BrandFlameText.resolve(),
                        )
                        val time = TimeFormat.parts(context, local.toLocalTime())
                        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
                            TokenText(time.main, TypographyTokens.DisplayTime, maxLines = 1)
                            time.suffix?.let { TokenText(it, TypographyTokens.LabelDisplay, color = ColorTokens.TextTertiary.resolve(), modifier = Modifier.padding(bottom = 12.dp)) }
                        }
                        schedule?.label?.takeIf { it.isNotBlank() }?.let {
                            TokenText(it, TypographyTokens.BodyS, color = ColorTokens.TextSecondary.resolve(), maxLines = 1)
                        }
                    }
                    CountdownRing(WakeTabRules.countdownFraction(left.seconds), TimeFormat.until(context, left))
                }
                schedule?.let { sch ->
                    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                        InfoChip("💪", context.getString(R.string.mode_detail_reps, sch.mode.totalReps))
                        InfoChip("⚡", ModeText.name(context, sch.mode.modeType ?: app.pushly.core.alarm.ModeType.RingUntilDone))
                        InfoChip("📅", ScheduleText.days(context, sch))
                    }
                }
            }
        }
    }
}

/** Time left until the alarm as a ring that fills up over the last 24 hours. */
@Composable
private fun CountdownRing(fraction: Float, text: String) {
    val track = Color.White.copy(alpha = 0.08f)
    val brush = heroGradient()
    val a11y = stringResource(R.string.wake_rings_in, text)
    Box(Modifier.size(92.dp).clearAndSetSemantics { contentDescription = a11y }, contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(92.dp)) {
            val stroke = Stroke(width = 8.dp.toPx(), cap = StrokeCap.Round)
            drawArc(track, 0f, 360f, false, style = stroke)
            drawArc(brush, -90f, 360f * fraction, false, style = stroke)
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            TokenText(stringResource(R.string.wake_in), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
            TokenText(text, TypographyTokens.LabelDisplay, maxLines = 1, modifier = Modifier.padding(horizontal = 8.dp))
        }
    }
}

@Composable
private fun InfoChip(glyph: String, text: String) {
    Row(
        Modifier.clip(CircleShape).background(Color.White.copy(alpha = 0.06f)).border(1.dp, ColorTokens.StrokeSubtle.resolve(), CircleShape)
            .padding(horizontal = SpacingTokens.S, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        TokenText(glyph, TypographyTokens.Caption, Modifier.clearAndSetSemantics {})
        TokenText(text, TypographyTokens.Caption, maxLines = 1)
    }
}

/** Streak, beaten this week, push-ups today — three equal tiles. Same as iOS `WakeStatsRow`. */
@Composable
private fun WakeStatsRow(summary: WakeSummary) {
    Row(Modifier.height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
        StatTile("🔥", "${summary.streak.current}", stringResource(R.string.wake_stat_streak),
            stringResource(R.string.wake_stat_best, summary.streak.best), ColorTokens.BrandFlameText, Modifier.weight(1f))
        StatTile("✅", "${WakeTabRules.beaten(summary)}/${WakeTabRules.challenges(summary)}", stringResource(R.string.wake_stat_week),
            stringResource(R.string.wake_stat_beaten), ColorTokens.StateSuccessText, Modifier.weight(1f))
        StatTile("💪", "${summary.repsToday ?: 0}", stringResource(R.string.wake_stat_pushups),
            stringResource(R.string.wake_stat_today), ColorTokens.BrandVoltText, Modifier.weight(1f))
    }
}

@Composable
private fun StatTile(glyph: String, value: String, title: String, sub: String, tint: TokenColor, modifier: Modifier) {
    val shape = RoundedCornerShape(RadiusTokens.L)
    Column(
        modifier.fillMaxHeight().clip(shape)
            .background(Brush.linearGradient(listOf(tint.resolve().copy(alpha = 0.12f), ColorTokens.BgSurface.resolve())))
            .border(1.dp, ColorTokens.StrokeSubtle.resolve(), shape).padding(SpacingTokens.Sm).semantics(mergeDescendants = true) {},
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        TokenText(glyph, TypographyTokens.TitleS, Modifier.clearAndSetSemantics {})
        TokenText(value, TypographyTokens.TitleL, color = tint.resolve(), maxLines = 1)
        TokenText(title, TypographyTokens.Caption, maxLines = 1)
        TokenText(sub, TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve(), maxLines = 1)
    }
}

/** "This week" card around the Monday–Sunday strip. */
@Composable
private fun WeekCard(summary: WakeSummary) {
    val shape = RoundedCornerShape(RadiusTokens.L)
    Column(
        Modifier.fillMaxWidth().clip(shape).background(ColorTokens.BgSurface.resolve()).border(1.dp, ColorTokens.StrokeSubtle.resolve(), shape)
            .padding(SpacingTokens.M),
        verticalArrangement = Arrangement.spacedBy(SpacingTokens.M),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TokenText(stringResource(R.string.wake_this_week), TypographyTokens.TitleS, Modifier.weight(1f))
            if (summary.streak.freezesAvailable > 0) {
                TokenText(stringResource(R.string.wake_freezes, summary.streak.freezesAvailable), TypographyTokens.Caption,
                    color = ColorTokens.BrandCyan.resolve())
            }
        }
        WeekStrip(summary)
    }
}

@Composable
private fun AlarmCard(
    item: WakeViewModel.Item,
    now: java.time.Instant,
    onClick: () -> Unit,
    onToggle: (Boolean) -> Unit,
    onSkip: () -> Unit,
    onUndoSkip: (String) -> Unit,
) {
    val context = LocalContext.current
    val s = item.schedule
    val dim = if (s.enabled) ColorTokens.TextPrimary else ColorTokens.TextDisabled
    val single = ScheduleText.singleTime(s)
    val title = single?.let { TimeFormat.short(context, it) } ?: item.next?.let {
        TimeFormat.short(context, it.instant.atZone(ZoneId.systemDefault()).toLocalTime())
    } ?: "—"
    val shape = RoundedCornerShape(RadiusTokens.L)
    val hero = heroGradient()
    Box(
        Modifier.fillMaxWidth().clip(shape).background(ColorTokens.BgSurface.resolve().copy(alpha = if (s.enabled) 1f else 0.6f))
            .border(1.dp, ColorTokens.StrokeSubtle.resolve(), shape),
    ) {
        if (s.enabled) {
            Box(Modifier.align(Alignment.CenterStart).padding(vertical = SpacingTokens.M).width(4.dp).height(56.dp).clip(CircleShape).background(hero))
        }
        Column(Modifier.padding(SpacingTokens.M), verticalArrangement = Arrangement.spacedBy(SpacingTokens.Sm)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(
                    Modifier.weight(1f).clickable(role = Role.Button, onClick = onClick),
                    verticalArrangement = Arrangement.spacedBy(SpacingTokens.Xs),
                ) {
                    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                        TokenText(title, TypographyTokens.Stat, color = dim.resolve(), maxLines = 1)
                        if (s.label.isNotBlank()) {
                            TokenText(s.label, TypographyTokens.BodyS, color = ColorTokens.TextSecondary.resolve(), maxLines = 1,
                                modifier = Modifier.padding(bottom = 8.dp))
                        }
                    }
                    DayDots(s)
                    TokenText(ModeText.summary(context, s.mode), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve(), maxLines = 1)
                }
                Spacer(Modifier.width(SpacingTokens.S))
                val onLabel = stringResource(R.string.wake_alarm_enabled)
                Switch(
                    checked = s.enabled,
                    onCheckedChange = onToggle,
                    colors = SwitchDefaults.colors(checkedTrackColor = ColorTokens.BrandFlame.resolve()),
                    modifier = Modifier.semantics {
                        contentDescription = "$onLabel, $title"
                        stateDescription = if (s.enabled) "on" else "off"
                    },
                )
            }
            if (s.enabled) {
                val skipped = item.skippedDate
                val next = item.next
                if (skipped != null) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        TokenText(stringResource(R.string.wake_skipped, skipped), TypographyTokens.Caption, color = ColorTokens.StateWarning.resolve(), modifier = Modifier.weight(1f))
                        GhostButton(stringResource(R.string.wake_undo_skip), onClick = { onUndoSkip(skipped) })
                    }
                } else if (next != null) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        TokenText("⏱ " + TimeFormat.until(context, Duration.between(now, next.instant)), TypographyTokens.Caption,
                            color = ColorTokens.TextSecondary.resolve(), modifier = Modifier.weight(1f))
                        GhostButton(stringResource(R.string.wake_skip_next), onClick = onSkip)
                    }
                }
                s.pause?.let {
                    TokenText(stringResource(R.string.wake_paused_until, it.to), TypographyTokens.Caption, color = ColorTokens.StateWarning.resolve())
                }
            }
        }
    }
}

/** M T W T F S S — the alarm's days lit, the others dimmed (one-off alarms show their date). */
@Composable
private fun DayDots(s: AlarmSchedule) {
    val context = LocalContext.current
    if (s.kind == app.pushly.core.alarm.AlarmKind.OneOff) {
        TokenText(ScheduleText.days(context, s), TypographyTokens.BodyS, color = ColorTokens.TextSecondary.resolve())
        return
    }
    val days = ScheduleText.days(context, s)
    val hero = heroGradient()
    Row(Modifier.clearAndSetSemantics { contentDescription = days }, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        java.time.DayOfWeek.entries.forEach { d ->
            val on = s.weekly?.time(d) != null
            Box(
                Modifier.size(20.dp).clip(CircleShape)
                    .then(if (on) Modifier.background(hero) else Modifier.background(Color.White.copy(alpha = 0.06f))),
                contentAlignment = Alignment.Center,
            ) {
                TokenText(TimeFormat.dayNarrow(d), TypographyTokens.Overline,
                    color = (if (on) ColorTokens.BgBase else ColorTokens.TextTertiary).resolve())
            }
        }
    }
}

/** 🔥 current wake streak (PS-10). */
@Composable
private fun StreakBadge(streak: Int) {
    val a11y = stringResource(R.string.wake_streak_a11y, streak)
    val flame = ColorTokens.BrandFlame.resolve()
    Row(
        Modifier.heightIn(min = 36.dp).clip(CircleShape).background(flame.copy(alpha = if (streak > 0) 0.16f else 0.06f))
            .border(1.dp, flame.copy(alpha = if (streak > 0) 0.5f else 0.15f), CircleShape)
            .padding(horizontal = SpacingTokens.Sm).clearAndSetSemantics { contentDescription = a11y },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        TokenText("🔥", TypographyTokens.BodyS)
        TokenText("$streak", TypographyTokens.TitleS, color = (if (streak > 0) ColorTokens.BrandFlameText else ColorTokens.TextTertiary).resolve())
    }
}

/**
 * This week, Monday–Sunday (PS-13): every day is the same soft disc; ✓ green = beaten, ✕ red = failed / missed,
 * – = skipped / paused, empty = no challenge; upcoming days are dimmed and today has a flame ring.
 */
@Composable
private fun WeekStrip(summary: WakeSummary) {
    val today = runCatching { java.time.LocalDate.parse(summary.today) }.getOrNull() ?: return
    val monday = today.minusDays((today.dayOfWeek.value - 1).toLong())
    val labels = listOf("M", "T", "W", "T", "F", "S", "S")
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
        (0 until 7).forEach { i ->
            val date = monday.plusDays(i.toLong())
            val status = summary.status(date.toString())
            val isToday = date == today
            val fill = when (status) {
                "succeeded" -> ColorTokens.StateSuccess.resolve()
                "failed", "missed" -> ColorTokens.StateDanger.resolve()
                else -> ColorTokens.BgElevated.resolve()
            }
            val glyph = when (status) {
                "succeeded" -> "✓"
                "failed", "missed" -> "✕"
                "skipped", "paused", "void" -> "–"
                else -> null
            }
            val label = stringResource(
                when (status) {
                    "succeeded" -> R.string.wake_day_beaten
                    "failed", "missed" -> R.string.wake_day_failed
                    "skipped" -> R.string.wake_day_skipped
                    "paused" -> R.string.wake_day_paused
                    else -> R.string.wake_day_none
                },
            )
            Column(
                Modifier.weight(1f).semantics(mergeDescendants = true) { contentDescription = "$date: $label" },
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(SpacingTokens.Xs),
            ) {
                val ring = ColorTokens.BrandFlame.resolve()
                Box(
                    Modifier.size(36.dp).border(if (isToday) 2.dp else 0.dp, ring, CircleShape).padding(3.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Box(
                        Modifier.fillMaxSize().alpha(if (date.isAfter(today)) 0.45f else 1f).clip(CircleShape).background(fill),
                        contentAlignment = Alignment.Center,
                    ) {
                        if (glyph != null) {
                            TokenText(
                                glyph,
                                TypographyTokens.LabelDisplay,
                                color = (if (status == "succeeded") ColorTokens.BgBase else ColorTokens.TextPrimary).resolve(),
                            )
                        }
                    }
                }
                TokenText(
                    labels[i],
                    TypographyTokens.Caption,
                    color = (if (isToday) ColorTokens.TextPrimary else ColorTokens.TextTertiary).resolve(),
                )
            }
        }
    }
}
