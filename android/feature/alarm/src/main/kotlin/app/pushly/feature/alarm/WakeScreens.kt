package app.pushly.feature.alarm

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
import app.pushly.core.designsystem.Pill
import app.pushly.core.designsystem.PrimaryButton
import app.pushly.core.designsystem.PushlyCard
import app.pushly.core.designsystem.ScreenTitle
import app.pushly.core.designsystem.SecondaryButton
import app.pushly.core.designsystem.SectionLabel
import app.pushly.core.designsystem.TokenText
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.SpacingTokens
import app.pushly.core.designsystem.generated.TypographyTokens
import app.pushly.core.designsystem.resolve
import app.pushly.feature.wakeflow.PoseRecorderScreen
import app.pushly.feature.wakeflow.TrainingScreen
import kotlinx.coroutines.delay
import java.time.Duration
import java.time.ZoneId

private sealed interface WakeRoute {
    data object List : WakeRoute
    data class Edit(val schedule: AlarmSchedule, val isNew: Boolean) : WakeRoute
    data object Permissions : WakeRoute
    data object Training : WakeRoute
    data object Recorder : WakeRoute
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
            onTraining = { route = WakeRoute.Training },
            onRecorder = { route = WakeRoute.Recorder },
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
        WakeRoute.Training -> TrainingScreen(onClose = { route = WakeRoute.List })
        WakeRoute.Recorder -> if (BuildConfig.DEBUG) PoseRecorderScreen(onClose = { route = WakeRoute.List })
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
    onTraining: () -> Unit,
    onRecorder: () -> Unit,
) {
    val s by vm.state.collectAsStateWithLifecycle()
    val health by vm.health.collectAsStateWithLifecycle()
    val notice by vm.notice.collectAsStateWithLifecycle()
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
            verticalArrangement = Arrangement.spacedBy(SpacingTokens.M),
        ) {
            ScreenTitle(stringResource(R.string.wake_title), token = TypographyTokens.DisplayM)

            health.forEach { issue -> HealthCard(issue, onFix = {
                if (issue in setOf(HealthIssue.ExactAlarmMissing, HealthIssue.FullScreenIntentMissing, HealthIssue.NotificationsBlocked)) {
                    onFixPermissions()
                } else {
                    runCatching { context.startActivity(AlarmPermissions.intentFor(context, issue)) }
                }
            }) }
            notice?.let { InlineBanner(stringResource(it), BannerKind.Info) }

            NextAlarmCard(s, onNew)

            SecondaryButton(stringResource(R.string.wake_free_training), onTraining)
            if (BuildConfig.DEBUG) GhostButton(stringResource(R.string.wake_pose_recorder), onRecorder)

            if (s.items.isNotEmpty()) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    SectionLabel(stringResource(R.string.wake_your_alarms), modifier = Modifier.weight(1f))
                    TokenText(
                        stringResource(R.string.wake_alarm_count, s.items.size, AlarmSchedule.MAX_ALARMS_PER_USER),
                        TypographyTokens.Caption,
                        color = ColorTokens.TextTertiary.resolve(),
                    )
                }
                s.items.forEach { item ->
                    AlarmCard(
                        item = item,
                        onClick = { onEdit(item.schedule) },
                        onToggle = { vm.setEnabled(item.schedule.id, it) },
                        onSkip = { vm.skipNext(item.schedule.id) },
                        onUndoSkip = { date -> vm.undoSkip(item.schedule.id, date) },
                    )
                }
                if (vm.canAddAlarm()) SecondaryButton("+ " + stringResource(R.string.wake_new_alarm), onNew)
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
        Column(Modifier.padding(SpacingTokens.L), verticalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
            if (next == null) {
                TokenText(stringResource(R.string.wake_no_alarm_title), TypographyTokens.DisplayM)
                TokenText(stringResource(R.string.wake_no_alarm_text), TypographyTokens.Body, color = ColorTokens.TextSecondary.resolve())
                Spacer(Modifier.padding(top = SpacingTokens.S))
                PrimaryButton(stringResource(R.string.wake_set_alarm), onNew)
            } else {
                val local = next.instant.atZone(ZoneId.systemDefault())
                val schedule = s.items.firstOrNull { it.schedule.id == next.alarmId }?.schedule
                Row(verticalAlignment = Alignment.CenterVertically) {
                    TokenText(
                        stringResource(R.string.wake_next_alarm, TimeFormat.dayShort(local.dayOfWeek)),
                        TypographyTokens.Overline,
                        color = ColorTokens.BrandFlameText.resolve(),
                        modifier = Modifier.weight(1f),
                    )
                    TokenText(TimeFormat.until(context, Duration.between(s.now, next.instant)), TypographyTokens.Caption, color = ColorTokens.TextSecondary.resolve())
                }
                val time = TimeFormat.parts(context, local.toLocalTime())
                Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                    TokenText(time.main, TypographyTokens.DisplayTime)
                    time.suffix?.let { TokenText(it, TypographyTokens.LabelDisplay, color = ColorTokens.TextTertiary.resolve(), modifier = Modifier.padding(bottom = 12.dp)) }
                }
                schedule?.let { sch ->
                    Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                        Pill(ModeText.name(context, sch.mode.modeType ?: app.pushly.core.alarm.ModeType.RingUntilDone))
                        Pill(context.getString(R.string.mode_detail_reps, sch.mode.totalReps))
                    }
                }
            }
        }
    }
}

@Composable
private fun AlarmCard(
    item: WakeViewModel.Item,
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
    PushlyCard(padding = SpacingTokens.M, modifier = Modifier.clickable(role = Role.Button, onClick = onClick)) {
        Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    TokenText(title, TypographyTokens.Stat, color = dim.resolve())
                    TokenText(
                        listOf(ScheduleText.days(context, s), s.label).filter { it.isNotBlank() }.joinToString(" · "),
                        TypographyTokens.BodyS,
                        color = ColorTokens.TextSecondary.resolve(),
                        maxLines = 2,
                    )
                    TokenText(ModeText.summary(context, s.mode), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
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
                if (skipped != null) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        TokenText(stringResource(R.string.wake_skipped, skipped), TypographyTokens.Caption, color = ColorTokens.StateWarning.resolve(), modifier = Modifier.weight(1f))
                        GhostButton(stringResource(R.string.wake_undo_skip), onClick = { onUndoSkip(skipped) })
                    }
                } else if (item.next != null) {
                    GhostButton(stringResource(R.string.wake_skip_next), onClick = onSkip)
                }
                s.pause?.let {
                    TokenText(stringResource(R.string.wake_paused_until, it.to), TypographyTokens.Caption, color = ColorTokens.StateWarning.resolve())
                }
            }
        }
    }
}

