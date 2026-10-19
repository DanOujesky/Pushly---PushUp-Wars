package app.pushly.feature.alarm

import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.TimePickerDefaults
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import app.pushly.core.alarm.AlarmPause
import app.pushly.core.alarm.AlarmSchedule
import app.pushly.core.alarm.AlarmSounds
import app.pushly.core.alarm.AlarmValidation
import app.pushly.core.alarm.ChallengeMode
import app.pushly.core.alarm.ModeType
import app.pushly.core.alarm.SaveResult
import app.pushly.core.alarm.WeeklyTimes
import app.pushly.core.designsystem.ArenaBackground
import app.pushly.core.designsystem.BannerKind
import app.pushly.core.designsystem.GhostButton
import app.pushly.core.designsystem.InlineBanner
import app.pushly.core.designsystem.PrimaryButton
import app.pushly.core.designsystem.PushlyCard
import app.pushly.core.designsystem.PushlyTextField
import app.pushly.core.designsystem.ScreenTitle
import app.pushly.core.designsystem.SecondaryButton
import app.pushly.core.designsystem.SectionLabel
import app.pushly.core.designsystem.TokenText
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.RadiusTokens
import app.pushly.core.designsystem.generated.SpacingTokens
import app.pushly.core.designsystem.generated.TypographyTokens
import app.pushly.core.designsystem.resolve
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId

/** Create / edit an alarm (doc 02 PS-21…26). No ads here (CLAUDE.md §4.5). */
@Composable
fun AlarmEditor(initial: AlarmSchedule, isNew: Boolean, vm: WakeViewModel, modifier: Modifier = Modifier, onDone: (saved: Boolean) -> Unit) {
    val context = LocalContext.current
    var draft by remember { mutableStateOf(initial) }
    var perDay by remember { mutableStateOf(ScheduleText.singleTime(initial) == null) }
    var errors by remember { mutableStateOf<Set<String>>(emptySet()) }
    var tooMany by remember { mutableStateOf(false) }
    var picking by remember { mutableStateOf<DayOfWeek?>(null) }
    var pickingAll by remember { mutableStateOf(false) }
    val weekly = draft.weekly ?: WeeklyTimes()
    val baseTime = ScheduleText.singleTime(draft) ?: DayOfWeek.entries.firstNotNullOfOrNull { weekly.time(it) } ?: "06:30"

    ArenaBackground(modifier, glow = ColorTokens.BrandFlame) {
        Column(Modifier.fillMaxSize()) {
            Row(Modifier.fillMaxWidth().padding(horizontal = SpacingTokens.S), verticalAlignment = Alignment.CenterVertically) {
                GhostButton(stringResource(R.string.editor_cancel), onClick = { onDone(false) })
            }
            Column(
                Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = SpacingTokens.Ml),
                verticalArrangement = Arrangement.spacedBy(SpacingTokens.L),
            ) {
                ScreenTitle(stringResource(if (isNew) R.string.editor_new else R.string.editor_edit), token = TypographyTokens.DisplayM)

                // Time + days (PS-21/22)
                if (!perDay) {
                    val t = TimeFormat.parse(baseTime) ?: LocalTime.of(6, 30)
                    val parts = TimeFormat.parts(context, t)
                    val pickLabel = stringResource(R.string.editor_pick_time)
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(RadiusTokens.L))
                            .background(ColorTokens.BgSurface.resolve())
                            .border(1.dp, ColorTokens.StrokeSubtle.resolve(), RoundedCornerShape(RadiusTokens.L))
                            .clickable(role = Role.Button, onClickLabel = pickLabel) { pickingAll = true }
                            .padding(vertical = SpacingTokens.M),
                        contentAlignment = Alignment.Center,
                    ) {
                        Row(verticalAlignment = Alignment.Bottom) {
                            TokenText(parts.main, TypographyTokens.DisplayTime)
                            parts.suffix?.let { TokenText(" $it", TypographyTokens.LabelDisplay, color = ColorTokens.TextTertiary.resolve()) }
                        }
                    }
                }
                Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.Sm)) {
                    SectionLabel(stringResource(R.string.editor_days))
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        DayOfWeek.entries.forEach { day ->
                            val on = weekly.time(day) != null
                            DayChip(day, on) {
                                draft = draft.copy(weekly = weekly.with(day, if (on) null else baseTime))
                            }
                        }
                    }
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        TokenText(stringResource(R.string.editor_per_day), TypographyTokens.Body, modifier = Modifier.weight(1f))
                        Switch(
                            checked = perDay,
                            onCheckedChange = { on ->
                                perDay = on
                                if (!on) {
                                    var w = WeeklyTimes()
                                    DayOfWeek.entries.forEach { d -> if (weekly.time(d) != null) w = w.with(d, baseTime) }
                                    draft = draft.copy(weekly = w)
                                }
                            },
                            colors = SwitchDefaults.colors(checkedTrackColor = ColorTokens.BrandFlame.resolve()),
                        )
                    }
                    if (perDay) {
                        PushlyCard(padding = SpacingTokens.S) {
                            Column {
                                DayOfWeek.entries.forEach { day ->
                                    val time = weekly.time(day)
                                    Row(
                                        Modifier
                                            .fillMaxWidth()
                                            .heightIn(min = 48.dp)
                                            .clickable(role = Role.Button) { picking = day }
                                            .padding(horizontal = SpacingTokens.S),
                                        verticalAlignment = Alignment.CenterVertically,
                                    ) {
                                        TokenText(TimeFormat.dayShort(day), TypographyTokens.Body, modifier = Modifier.weight(1f))
                                        TokenText(
                                            TimeFormat.short(context, time) ?: stringResource(R.string.editor_day_off),
                                            TypographyTokens.TitleS,
                                            color = (if (time == null) ColorTokens.TextDisabled else ColorTokens.TextPrimary).resolve(),
                                        )
                                    }
                                }
                            }
                        }
                    }
                }

                PushlyTextField(
                    draft.label,
                    { draft = draft.copy(label = it.take(AlarmSchedule.MAX_LABEL_LENGTH)) },
                    stringResource(R.string.editor_label),
                    placeholder = stringResource(R.string.editor_label_placeholder),
                )

                ModeSection(draft.mode) { draft = draft.copy(mode = it) }

                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        TokenText(stringResource(R.string.wake_counts), TypographyTokens.Body)
                        TokenText(stringResource(R.string.editor_counts_hint), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
                    }
                    Switch(
                        checked = draft.countsForChallenge,
                        onCheckedChange = { draft = draft.copy(countsForChallenge = it) },
                        colors = SwitchDefaults.colors(checkedTrackColor = ColorTokens.BrandFlame.resolve()),
                    )
                }

                SoundSection(draft.sound.id) { draft = draft.copy(sound = draft.sound.copy(id = it)) }

                PauseSection(draft.pause) { draft = draft.copy(pause = it) }

                if (tooMany) InlineBanner(stringResource(R.string.editor_too_many))
                if (errors.isNotEmpty()) InlineBanner(stringResource(errorText(errors)))

                Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.Sm)) {
                    SecondaryButton(stringResource(R.string.editor_test), onClick = { vm.testAlarm(draft) })
                    if (!isNew) {
                        GhostButton(stringResource(R.string.editor_delete), onClick = {
                            vm.delete(draft.id)
                            onDone(false)
                        }, modifier = Modifier.align(Alignment.CenterHorizontally))
                    }
                }
            }
            PrimaryButton(
                stringResource(R.string.editor_save),
                onClick = {
                    when (val r = vm.save(draft)) {
                        is SaveResult.Saved -> onDone(true)
                        is SaveResult.Invalid -> errors = r.errors
                        SaveResult.TooManyAlarms -> tooMany = true
                    }
                },
                modifier = Modifier.padding(horizontal = SpacingTokens.Ml).padding(bottom = SpacingTokens.S, top = SpacingTokens.S),
            )
        }
    }

    if (pickingAll) {
        TimeDialog(TimeFormat.parse(baseTime) ?: LocalTime.of(6, 30), onDismiss = { pickingAll = false }) { t ->
            var w = WeeklyTimes()
            DayOfWeek.entries.forEach { d -> if (weekly.time(d) != null) w = w.with(d, TimeFormat.hhmm(t)) }
            if (w.isEmpty) w = w.with(DayOfWeek.MONDAY, TimeFormat.hhmm(t))
            draft = draft.copy(weekly = w)
            pickingAll = false
        }
    }
    picking?.let { day ->
        TimeDialog(TimeFormat.parse(weekly.time(day) ?: baseTime) ?: LocalTime.of(6, 30), onDismiss = { picking = null }) { t ->
            draft = draft.copy(weekly = weekly.with(day, TimeFormat.hhmm(t)))
            picking = null
        }
    }
}

private fun errorText(errors: Set<String>): Int = when {
    "weekly.empty" in errors -> R.string.editor_error_days
    errors.any { it.startsWith("mode.") } -> R.string.editor_error_mode
    else -> R.string.editor_error_generic
}

@Composable
private fun RowScope.DayChip(day: DayOfWeek, on: Boolean, onClick: () -> Unit) {
    val shape = RoundedCornerShape(RadiusTokens.S)
    Box(
        Modifier
            .weight(1f)
            .heightIn(min = 48.dp)
            .clip(shape)
            .background((if (on) ColorTokens.BrandFlame else ColorTokens.BgSurface).resolve())
            .border(1.dp, (if (on) ColorTokens.BrandFlame else ColorTokens.StrokeSubtle).resolve(), shape)
            .clickable(role = Role.Checkbox, onClick = onClick)
            .semantics {
                contentDescription = TimeFormat.dayShort(day)
                selected = on
            },
        contentAlignment = Alignment.Center,
    ) {
        TokenText(
            TimeFormat.dayNarrow(day),
            TypographyTokens.TitleS,
            color = if (on) androidx.compose.ui.graphics.Color.White else ColorTokens.TextSecondary.resolve(),
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TimeDialog(initial: LocalTime, onDismiss: () -> Unit, onPicked: (LocalTime) -> Unit) {
    val context = LocalContext.current
    val state = rememberTimePickerState(initial.hour, initial.minute, android.text.format.DateFormat.is24HourFormat(context))
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = ColorTokens.BgElevated.resolve(),
        confirmButton = {
            TextButton(onClick = { onPicked(LocalTime.of(state.hour, state.minute)) }) {
                TokenText(stringResource(R.string.editor_ok), TypographyTokens.Button, color = ColorTokens.BrandFlameText.resolve())
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                TokenText(stringResource(R.string.editor_cancel), TypographyTokens.Button, color = ColorTokens.TextSecondary.resolve())
            }
        },
        text = {
            TimePicker(
                state = state,
                colors = TimePickerDefaults.colors(
                    clockDialColor = ColorTokens.BgSurface.resolve(),
                    selectorColor = ColorTokens.BrandFlame.resolve(),
                    timeSelectorSelectedContainerColor = ColorTokens.BrandFlame.resolve().copy(alpha = 0.25f),
                    timeSelectorUnselectedContainerColor = ColorTokens.BgSurface.resolve(),
                    periodSelectorSelectedContainerColor = ColorTokens.BrandFlame.resolve().copy(alpha = 0.25f),
                ),
            )
        },
    )
}

@Composable
private fun ModeSection(mode: ChallengeMode, onChange: (ChallengeMode) -> Unit) {
    val context = LocalContext.current
    val type = mode.modeType ?: ModeType.RingUntilDone
    Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.Sm)) {
        SectionLabel(stringResource(R.string.editor_mode))
        ModeType.entries.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                row.forEach { t ->
                    val selected = t == type
                    val shape = RoundedCornerShape(RadiusTokens.M)
                    Box(
                        Modifier
                            .weight(1f)
                            .heightIn(min = 48.dp)
                            .clip(shape)
                            .background((if (selected) ColorTokens.BrandFlame else ColorTokens.BgSurface).resolve().copy(alpha = if (selected) 0.18f else 1f))
                            .border(if (selected) 1.5.dp else 1.dp, (if (selected) ColorTokens.BrandFlame else ColorTokens.StrokeSubtle).resolve(), shape)
                            .clickable(role = Role.RadioButton) { if (!selected) onChange(ChallengeMode.defaults(t, mode.targetReps ?: 20)) }
                            .semantics { this.selected = selected }
                            .padding(horizontal = SpacingTokens.Sm, vertical = SpacingTokens.S),
                        contentAlignment = Alignment.CenterStart,
                    ) {
                        TokenText(ModeText.name(context, t), TypographyTokens.BodyS, color = (if (selected) ColorTokens.BrandFlameText else ColorTokens.TextPrimary).resolve())
                    }
                }
                if (row.size == 1) Box(Modifier.weight(1f))
            }
        }
        TokenText(ModeText.description(context, type), TypographyTokens.Caption, color = ColorTokens.TextSecondary.resolve())
        PushlyCard(padding = SpacingTokens.M) {
            Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                when (type) {
                    ModeType.RingUntilDone -> Stepper(R.string.editor_target_reps, mode.targetReps ?: 20, 5..100, 5) { onChange(mode.copy(targetReps = it)) }
                    ModeType.BeatTheClock -> {
                        Stepper(R.string.editor_target_reps, mode.targetReps ?: 20, 5..100, 5) { onChange(mode.copy(targetReps = it)) }
                        Stepper(R.string.editor_window, mode.windowSeconds ?: 120, 30..600, 30) { onChange(mode.copy(windowSeconds = it)) }
                        if (AlarmValidation.isVeryHard(mode)) InlineBanner(stringResource(R.string.editor_very_hard), BannerKind.Warning)
                    }
                    ModeType.Sprint -> {
                        Choice(R.string.editor_window, mode.windowSeconds ?: 60, listOf(30, 60, 120)) { onChange(mode.copy(windowSeconds = it)) }
                        Stepper(R.string.editor_minimum, mode.minimumReps ?: 15, 5..100, 5) { onChange(mode.copy(minimumReps = it)) }
                    }
                    ModeType.Sets -> {
                        Stepper(R.string.editor_sets, mode.sets ?: 3, 2..5, 1) { onChange(mode.copy(sets = it)) }
                        Stepper(R.string.editor_reps_per_set, mode.repsPerSet ?: 10, 5..50, 5) { onChange(mode.copy(repsPerSet = it)) }
                        Stepper(R.string.editor_rest, mode.restSeconds ?: 45, 15..180, 15) { onChange(mode.copy(restSeconds = it)) }
                    }
                    ModeType.Escalation -> {
                        Stepper(R.string.editor_target_reps, mode.targetReps ?: 20, 5..100, 5) { onChange(mode.copy(targetReps = it)) }
                        Stepper(R.string.editor_snooze_adds, mode.snoozeAddsReps ?: 5, 1..20, 1) { onChange(mode.copy(snoozeAddsReps = it)) }
                        Stepper(R.string.editor_snooze_minutes, mode.snoozeMinutes ?: 5, 1..10, 1) { onChange(mode.copy(snoozeMinutes = it)) }
                        Stepper(R.string.editor_max_snoozes, mode.maxSnoozes ?: 3, 1..5, 1) { onChange(mode.copy(maxSnoozes = it)) }
                    }
                }
            }
        }
    }
}

@Composable
private fun Stepper(label: Int, value: Int, range: IntRange, step: Int, onChange: (Int) -> Unit) {
    val name = stringResource(label)
    Row(verticalAlignment = Alignment.CenterVertically) {
        TokenText(name, TypographyTokens.Body, modifier = Modifier.weight(1f))
        RoundButton("−", stringResource(R.string.editor_decrease, name), enabled = value > range.first) {
            onChange((value - step).coerceAtLeast(range.first))
        }
        TokenText(value.toString(), TypographyTokens.TitleM, modifier = Modifier.widthIn(min = 56.dp).padding(horizontal = SpacingTokens.S).semantics { stateDescription = value.toString() })
        RoundButton("+", stringResource(R.string.editor_increase, name), enabled = value < range.last) {
            onChange((value + step).coerceAtMost(range.last))
        }
    }
}

@Composable
private fun Choice(label: Int, value: Int, options: List<Int>, onChange: (Int) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
        TokenText(stringResource(label), TypographyTokens.Body)
        Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
            options.forEach { o ->
                val selected = o == value
                val shape = RoundedCornerShape(RadiusTokens.S)
                Box(
                    Modifier
                        .weight(1f)
                        .heightIn(min = 48.dp)
                        .clip(shape)
                        .background((if (selected) ColorTokens.BrandFlame else ColorTokens.BgElevated).resolve())
                        .clickable(role = Role.RadioButton) { onChange(o) }
                        .semantics { this.selected = selected },
                    contentAlignment = Alignment.Center,
                ) { TokenText("$o s", TypographyTokens.TitleS) }
            }
        }
    }
}

@Composable
private fun RoundButton(symbol: String, description: String, enabled: Boolean, onClick: () -> Unit) {
    Box(
        Modifier
            .size(48.dp)
            .clip(CircleShape)
            .background(ColorTokens.BgElevated.resolve())
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .semantics { contentDescription = description },
        contentAlignment = Alignment.Center,
    ) {
        TokenText(symbol, TypographyTokens.TitleM, color = (if (enabled) ColorTokens.TextPrimary else ColorTokens.TextDisabled).resolve())
    }
}

@Composable
private fun SoundSection(selectedId: String, onSelect: (String) -> Unit) {
    val context = LocalContext.current
    var player by remember { mutableStateOf<MediaPlayer?>(null) }
    DisposableEffect(Unit) { onDispose { player?.release() } }
    Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.Sm)) {
        SectionLabel(stringResource(R.string.editor_sound))
        AlarmSounds.bundled.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                row.forEach { id ->
                    val selected = id == selectedId
                    val name = stringResource(soundName(id))
                    val shape = RoundedCornerShape(RadiusTokens.M)
                    Box(
                        Modifier
                            .weight(1f)
                            .heightIn(min = 48.dp)
                            .clip(shape)
                            .background(ColorTokens.BgSurface.resolve())
                            .border(if (selected) 1.5.dp else 1.dp, (if (selected) ColorTokens.BrandFlame else ColorTokens.StrokeSubtle).resolve(), shape)
                            .clickable(role = Role.RadioButton) {
                                onSelect(id)
                                player?.release()
                                player = runCatching {
                                    MediaPlayer().apply {
                                        setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build())
                                        setDataSource(context, Uri.parse("android.resource://${context.packageName}/${AlarmRingService.soundResource(id)}"))
                                        prepare()
                                        setVolume(0.6f, 0.6f)
                                        start()
                                    }
                                }.getOrNull()
                            }
                            .semantics {
                                this.selected = selected
                                contentDescription = name
                            }
                            .padding(horizontal = SpacingTokens.M),
                        contentAlignment = Alignment.CenterStart,
                    ) {
                        TokenText(name, TypographyTokens.Body, color = (if (selected) ColorTokens.BrandFlameText else ColorTokens.TextPrimary).resolve())
                    }
                }
            }
        }
    }
}

private fun soundName(id: String): Int = when (AlarmSounds.resourceName(id)) {
    "rise" -> R.string.sound_rise
    "arena" -> R.string.sound_arena
    "classic" -> R.string.sound_classic
    else -> R.string.sound_pulse
}

/** Pause the alarm for a few days from tomorrow (PS-25). Max 30 days (doc 04 §2). */
@Composable
private fun PauseSection(pause: AlarmPause?, onChange: (AlarmPause?) -> Unit) {
    val tomorrow = LocalDate.now(ZoneId.systemDefault()).plusDays(1)
    val currentDays = pause?.let { p ->
        runCatching { java.time.temporal.ChronoUnit.DAYS.between(LocalDate.parse(p.from), LocalDate.parse(p.to)).toInt() + 1 }.getOrNull()
    }
    Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.Sm)) {
        SectionLabel(stringResource(R.string.editor_pause))
        Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
            listOf<Int?>(null, 3, 7, 14).forEach { days ->
                val selected = days == currentDays || (days == null && pause == null)
                val shape = RoundedCornerShape(RadiusTokens.S)
                Box(
                    Modifier
                        .weight(1f)
                        .heightIn(min = 48.dp)
                        .clip(shape)
                        .background((if (selected) ColorTokens.BrandFlame else ColorTokens.BgSurface).resolve().copy(alpha = if (selected) 0.18f else 1f))
                        .border(1.dp, (if (selected) ColorTokens.BrandFlame else ColorTokens.StrokeSubtle).resolve(), shape)
                        .clickable(role = Role.RadioButton) {
                            onChange(days?.let { AlarmPause(tomorrow.toString(), tomorrow.plusDays((it - 1).toLong()).toString()) })
                        }
                        .semantics { this.selected = selected },
                    contentAlignment = Alignment.Center,
                ) {
                    TokenText(
                        if (days == null) stringResource(R.string.editor_pause_off) else stringResource(R.string.editor_pause_days, days),
                        TypographyTokens.Caption,
                    )
                }
            }
        }
    }
}

