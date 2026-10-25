package app.pushly.feature.wakeflow

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.pushly.core.designsystem.GhostButton
import app.pushly.core.designsystem.Pill
import app.pushly.core.designsystem.PrimaryButton
import app.pushly.core.designsystem.PushlyCard
import app.pushly.core.designsystem.PushlyTextField
import app.pushly.core.designsystem.ScreenTitle
import app.pushly.core.designsystem.SecondaryButton
import app.pushly.core.designsystem.SectionLabel
import app.pushly.core.designsystem.SideViewNotice
import app.pushly.core.designsystem.TokenText
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.SpacingTokens
import app.pushly.core.designsystem.generated.TouchTarget
import app.pushly.core.designsystem.generated.TypographyTokens
import app.pushly.core.designsystem.resolve
import app.pushly.engine.rep.RepState
import java.util.UUID
import kotlinx.coroutines.delay

private sealed interface WorkoutRoute {
    data object Hub : WorkoutRoute
    data class Detail(val workout: Workout) : WorkoutRoute
    data class Edit(val workout: Workout) : WorkoutRoute
    data class Run(val workout: Workout) : WorkoutRoute
    data object Free : WorkoutRoute
}

/**
 * Workouts hub (D-069), same as iOS `WorkoutsView`: free training, ready-made workouts and the user's own. Every
 * push-up done here is one training session and counts for the day — stats, leaderboards, Clan War (side view).
 */
@Composable
fun WorkoutsScreen(onClose: () -> Unit) {
    val context = LocalContext.current
    val store = remember { WorkoutStore(context) }
    val presets = remember { Workout.presets(context) }
    var mine by remember { mutableStateOf(store.load()) }
    var route by remember { mutableStateOf<WorkoutRoute>(WorkoutRoute.Hub) }
    val back = { route = WorkoutRoute.Hub }

    when (val r = route) {
        WorkoutRoute.Hub -> {
            BackHandler(onBack = onClose)
            WorkoutHub(presets, mine, onClose, onOpen = { route = WorkoutRoute.Detail(it) },
                onCreate = { route = WorkoutRoute.Edit(Workout.blank()) }, onFree = { route = WorkoutRoute.Free })
        }
        is WorkoutRoute.Detail -> {
            BackHandler(onBack = back)
            val myVersion = stringResource(R.string.workout_my_version, r.workout.name)
            WorkoutDetail(
                r.workout,
                onBack = back,
                onStart = { route = WorkoutRoute.Run(r.workout) },
                onEdit = {
                    val w = r.workout
                    route = WorkoutRoute.Edit(if (w.isPreset) w.copy(id = UUID.randomUUID().toString(), name = myVersion, isPreset = false) else w)
                },
                onDelete = if (r.workout.isPreset) null else ({
                    mine = store.delete(r.workout.id)
                    route = WorkoutRoute.Hub
                }),
            )
        }
        is WorkoutRoute.Edit -> {
            BackHandler(onBack = back)
            WorkoutEditor(r.workout, onCancel = back, onSave = {
                mine = store.upsert(it)
                route = WorkoutRoute.Hub
            })
        }
        is WorkoutRoute.Run -> WorkoutRun(r.workout, onClose = back)
        WorkoutRoute.Free -> TrainingScreen(onClose = back)
    }
}

@Composable
private fun WorkoutHub(
    presets: List<Workout>,
    mine: List<Workout>,
    onClose: () -> Unit,
    onOpen: (Workout) -> Unit,
    onCreate: () -> Unit,
    onFree: () -> Unit,
) {
    Column(
        Modifier.fillMaxSize().safeDrawingPadding().verticalScroll(rememberScrollState()).padding(SpacingTokens.L),
        verticalArrangement = Arrangement.spacedBy(SpacingTokens.M),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            ScreenTitle(stringResource(R.string.workouts_title), Modifier.weight(1f))
            GhostButton(stringResource(R.string.workouts_close), onClose)
        }
        SideViewNotice()
        TokenText(stringResource(R.string.workouts_side_counts), TypographyTokens.Caption, color = ColorTokens.TextSecondary.resolve())
        PushlyCard(Modifier.fillMaxWidth().clickable(onClick = onFree)) {
            Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
                TokenText(stringResource(R.string.workouts_free), TypographyTokens.TitleS)
                TokenText(stringResource(R.string.workouts_free_sub), TypographyTokens.Caption, color = ColorTokens.TextSecondary.resolve())
            }
        }
        SectionLabel(stringResource(R.string.workouts_ready))
        presets.forEach { WorkoutRow(it) { onOpen(it) } }
        Row(verticalAlignment = Alignment.CenterVertically) {
            SectionLabel(stringResource(R.string.workouts_mine), Modifier.weight(1f))
            TextButton(onClick = onCreate, modifier = Modifier.heightIn(min = TouchTarget.Minimum)) {
                TokenText(stringResource(R.string.workouts_create), TypographyTokens.Button, color = ColorTokens.BrandFlameText.resolve())
            }
        }
        if (mine.isEmpty()) {
            TokenText(stringResource(R.string.workouts_empty), TypographyTokens.BodyS, color = ColorTokens.TextTertiary.resolve())
            SecondaryButton(stringResource(R.string.workouts_create_long), onCreate)
        }
        mine.forEach { WorkoutRow(it) { onOpen(it) } }
    }
}

@Composable
private fun WorkoutRow(w: Workout, onClick: () -> Unit) {
    PushlyCard(Modifier.fillMaxWidth().clickable(onClick = onClick)) {
        Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
            TokenText(w.name, TypographyTokens.TitleS)
            if (w.description.isNotEmpty()) {
                TokenText(w.description, TypographyTokens.Caption, color = ColorTokens.TextSecondary.resolve())
            }
            WorkoutPills(w)
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun WorkoutPills(w: Workout) {
    val context = LocalContext.current
    FlowRow(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Xs), verticalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
        Pill(pluralStringResource(R.plurals.workout_sets_count, w.sets.size, w.sets.size))
        w.plannedReps?.let { Pill(stringResource(R.string.workout_pushups, it), color = ColorTokens.BrandFlameText) }
        Pill(WorkoutSession.duration(context, w.estimatedSeconds))
        w.everyS?.let { Pill(stringResource(R.string.workout_every, it), color = ColorTokens.BrandVoltText) }
    }
}

@Composable
private fun WorkoutDetail(w: Workout, onBack: () -> Unit, onStart: () -> Unit, onEdit: () -> Unit, onDelete: (() -> Unit)?) {
    val context = LocalContext.current
    var confirm by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxSize().safeDrawingPadding().padding(SpacingTokens.L), verticalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TokenText(w.name, TypographyTokens.TitleL, Modifier.weight(1f))
            GhostButton(stringResource(R.string.workouts_close), onBack)
        }
        if (w.description.isNotEmpty()) TokenText(w.description, TypographyTokens.BodyS, color = ColorTokens.TextSecondary.resolve())
        WorkoutPills(w)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
            w.sets.forEachIndexed { i, s ->
                Row(Modifier.fillMaxWidth().heightIn(min = 36.dp), verticalAlignment = Alignment.CenterVertically) {
                    TokenText(stringResource(R.string.workout_set_n, i + 1), TypographyTokens.BodyS, Modifier.widthIn(min = 64.dp),
                        color = ColorTokens.TextTertiary.resolve())
                    TokenText(WorkoutSession.setLabel(context, s), TypographyTokens.TitleS, Modifier.weight(1f))
                    if (w.everyS == null && i < w.sets.size - 1 && s.restS > 0) {
                        TokenText(stringResource(R.string.workout_rest_after, s.restS), TypographyTokens.Caption,
                            color = ColorTokens.TextTertiary.resolve())
                    }
                }
            }
        }
        PrimaryButton(stringResource(R.string.workout_start), onStart)
        Row {
            GhostButton(stringResource(if (w.isPreset) R.string.workout_copy_edit else R.string.workout_edit), onEdit)
            if (onDelete != null) {
                Spacer(Modifier.weight(1f))
                GhostButton(stringResource(R.string.workout_delete), { confirm = true })
            }
        }
    }
    if (confirm && onDelete != null) {
        AlertDialog(
            onDismissRequest = { confirm = false },
            title = { Text(stringResource(R.string.workout_delete_q)) },
            confirmButton = { TextButton(onClick = { confirm = false; onDelete() }) { Text(stringResource(R.string.workout_delete)) } },
            dismissButton = { TextButton(onClick = { confirm = false }) { Text(stringResource(R.string.workout_cancel)) } },
        )
    }
}

@Composable
private fun WorkoutEditor(initial: Workout, onCancel: () -> Unit, onSave: (Workout) -> Unit) {
    val context = LocalContext.current
    var w by remember { mutableStateOf(initial) }
    fun setAt(i: Int, change: (WorkoutSet) -> WorkoutSet) {
        if (i in w.sets.indices) w = w.copy(sets = w.sets.toMutableList().also { it[i] = change(it[i]) })
    }
    val emom = w.everyS != null
    Column(Modifier.fillMaxSize().safeDrawingPadding()) {
        Row(Modifier.padding(horizontal = SpacingTokens.L, vertical = SpacingTokens.S), verticalAlignment = Alignment.CenterVertically) {
            GhostButton(stringResource(R.string.workout_cancel), onCancel)
            TokenText(stringResource(if (initial.name.isEmpty()) R.string.workout_editor_new else R.string.workout_editor_edit),
                TypographyTokens.TitleS, Modifier.weight(1f).padding(horizontal = SpacingTokens.S))
            PrimaryButton(stringResource(R.string.workout_save), {
                val last = w.sets.size - 1
                onSave(w.copy(name = w.name.trim(), description = w.description.trim(),
                    sets = w.sets.mapIndexed { i, s -> if (i == last || emom) s.copy(restS = 0) else s }))
            }, Modifier.widthIn(max = 120.dp), enabled = w.validationErrors.isEmpty())
        }
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(SpacingTokens.L),
            verticalArrangement = Arrangement.spacedBy(SpacingTokens.M),
        ) {
            PushlyTextField(w.name, { w = w.copy(name = it.take(40)) }, stringResource(R.string.workout_name),
                placeholder = stringResource(R.string.workout_name_hint))
            PushlyTextField(w.description, { w = w.copy(description = it.take(140)) }, stringResource(R.string.workout_note),
                placeholder = stringResource(R.string.workout_note_hint))
            Row(Modifier.fillMaxWidth().heightIn(min = TouchTarget.Minimum), verticalAlignment = Alignment.CenterVertically) {
                TokenText(stringResource(R.string.workout_emom), TypographyTokens.BodyS, Modifier.weight(1f))
                Switch(emom, onCheckedChange = { on ->
                    w = if (on) {
                        w.copy(everyS = w.everyS ?: 60, sets = w.sets.map { if (it.kind != SetKind.REPS) WorkoutSet(SetKind.REPS, 10, 0) else it })
                    } else {
                        w.copy(everyS = null)
                    }
                }, colors = SwitchDefaults.colors(checkedTrackColor = ColorTokens.BrandFlame.resolve()))
            }
            if (emom) {
                NumberStepper(stringResource(R.string.workout_emom_every, w.everyS ?: 60), w.everyS ?: 60, Workout.EVERY_RANGE, 5) {
                    w = w.copy(everyS = it)
                }
            }
            TokenText(stringResource(if (emom) R.string.workout_emom_help else R.string.workout_rest_help), TypographyTokens.Caption,
                color = ColorTokens.TextTertiary.resolve())
            w.sets.forEachIndexed { i, s ->
                PushlyCard(Modifier.fillMaxWidth()) {
                    Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                        SectionLabel(stringResource(R.string.workout_set_n, i + 1))
                        if (!emom) {
                            Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
                                listOf(SetKind.REPS to R.string.workout_kind_reps, SetKind.AMRAP to R.string.workout_kind_amrap,
                                    SetKind.TIMED to R.string.workout_kind_timed).forEach { (kind, label) ->
                                    FilterChip(selected = s.kind == kind, onClick = {
                                        if (s.kind != kind) {
                                            setAt(i) {
                                                it.copy(kind = kind, target = when (kind) {
                                                    SetKind.REPS -> 10
                                                    SetKind.TIMED -> 30
                                                    SetKind.AMRAP -> 0
                                                })
                                            }
                                        }
                                    }, label = { Text(stringResource(label)) }, modifier = Modifier.heightIn(min = TouchTarget.Minimum))
                                }
                            }
                        }
                        when (s.kind) {
                            SetKind.REPS -> NumberStepper(stringResource(R.string.workout_pushups, s.target), s.target, 1..Workout.MAX_TARGET_REPS, 1) { v ->
                                setAt(i) { it.copy(target = v) }
                            }
                            SetKind.TIMED -> NumberStepper(stringResource(R.string.workout_target_timed, s.target), s.target, Workout.TIMED_RANGE, 5) { v ->
                                setAt(i) { it.copy(target = v) }
                            }
                            SetKind.AMRAP -> TokenText(stringResource(R.string.workout_amrap_help), TypographyTokens.Caption,
                                color = ColorTokens.TextSecondary.resolve())
                        }
                        if (!emom && i < w.sets.size - 1) {
                            NumberStepper(stringResource(R.string.workout_rest, s.restS), s.restS, 0..Workout.MAX_REST_S, 5) { v ->
                                setAt(i) { it.copy(restS = v) }
                            }
                        }
                        Row {
                            if (w.sets.size < Workout.MAX_SETS) {
                                GhostButton(stringResource(R.string.workout_duplicate), { w = duplicate(w, i, emom) })
                            }
                            Spacer(Modifier.weight(1f))
                            if (w.sets.size > 1) {
                                GhostButton(stringResource(R.string.workout_remove), {
                                    w = w.copy(sets = w.sets.toMutableList().also { it.removeAt(i) })
                                })
                            }
                        }
                    }
                }
            }
            if (w.sets.isNotEmpty() && w.sets.size < Workout.MAX_SETS) {
                SecondaryButton(stringResource(R.string.workout_add_set), { w = duplicate(w, w.sets.size - 1, emom) })
            }
            val summary = buildList {
                add(context.resources.getQuantityString(R.plurals.workout_sets_count, w.sets.size, w.sets.size))
                w.plannedReps?.let { add(context.getString(R.string.workout_pushups, it)) }
                add(WorkoutSession.duration(context, w.estimatedSeconds))
            }.joinToString(" · ")
            TokenText(summary, TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
        }
    }
}

private fun duplicate(w: Workout, i: Int, emom: Boolean): Workout {
    if (i !in w.sets.indices || w.sets.size >= Workout.MAX_SETS) return w
    val list = w.sets.toMutableList()
    var copy = list[i]
    if (copy.restS == 0 && !emom) copy = copy.copy(restS = 60)
    if (i == list.size - 1 && list[i].restS == 0 && !emom) list[i] = list[i].copy(restS = 60)
    list.add(i + 1, copy)
    return w.copy(sets = list)
}

@Composable
private fun NumberStepper(label: String, value: Int, range: IntRange, step: Int, onChange: (Int) -> Unit) {
    val less = stringResource(R.string.workout_minus)
    val more = stringResource(R.string.workout_plus)
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        TokenText(label, TypographyTokens.TitleS, Modifier.weight(1f))
        TextButton(
            onClick = { onChange((value - step).coerceIn(range)) },
            enabled = value > range.first,
            modifier = Modifier.heightIn(min = TouchTarget.Minimum).widthIn(min = TouchTarget.Minimum).semantics { contentDescription = less },
        ) { TokenText("−", TypographyTokens.TitleM, color = ColorTokens.TextPrimary.resolve()) }
        TextButton(
            onClick = { onChange((value + step).coerceIn(range)) },
            enabled = value < range.last,
            modifier = Modifier.heightIn(min = TouchTarget.Minimum).widthIn(min = TouchTarget.Minimum).semantics { contentDescription = more },
        ) { TokenText("+", TypographyTokens.TitleM, color = ColorTokens.TextPrimary.resolve()) }
    }
}

@Composable
private fun WorkoutRun(workout: Workout, onClose: () -> Unit) {
    val context = LocalContext.current
    val session = remember { WorkoutSession(workout, context) }
    DisposableEffect(Unit) { onDispose { session.release() } }
    val snap by session.snapshot.collectAsStateWithLifecycle()
    val completed by session.completed.collectAsStateWithLifecycle()
    val reps by session.reps.state.collectAsStateWithLifecycle()
    val services = SessionServices.shared
    var anchor by remember { mutableStateOf<ServerAnchor?>(null) }
    var sessionId by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) { anchor = services?.anchor() }
    LaunchedEffect(Unit) {
        while (true) {
            delay(200)
            session.tick()
        }
    }
    LaunchedEffect(reps.repState) { if (reps.repState != RepState.NotReady) session.inPosition() }
    LaunchedEffect(completed) {
        if (completed && session.reps.state.value.counted > 0) sessionId = services?.submitTraining(session.reps, anchor)
    }
    BackHandler { if (snap.phase == WorkoutRunner.Phase.Ready) onClose() else session.finish() }
    if (completed) {
        TrainingSummary(session.reps.summary(), services, sessionId, onClose, workout, session.runner.results.toList(),
            frontReps = reps.frontReps)
        return
    }
    RepSessionScreen(session.reps, speakCount = false) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            when {
                snap.phase == WorkoutRunner.Phase.Set && workout.everyS == null && session.runner.currentSet.kind != SetKind.TIMED ->
                    GhostButton(stringResource(R.string.workout_end_set), { session.endSet() })
                snap.phase == WorkoutRunner.Phase.Rest && workout.everyS == null ->
                    GhostButton(stringResource(R.string.workout_skip_rest), { session.skipRest() })
            }
            Spacer(Modifier.weight(1f))
            if (snap.phase == WorkoutRunner.Phase.Ready && reps.counted == 0) {
                PrimaryButton(stringResource(R.string.workouts_close), onClose, Modifier.widthIn(max = 160.dp))
            } else {
                PrimaryButton(stringResource(R.string.workout_finish), { session.finish() }, Modifier.widthIn(max = 160.dp))
            }
        }
    }
}

/** Per-set results on the summary (same as iOS `WorkoutSetResults`). */
@Composable
internal fun WorkoutSetResults(workout: Workout, sets: List<WorkoutRunner.SetResult>) {
    PushlyCard(Modifier.fillMaxWidth()) {
        Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
            TokenText(stringResource(R.string.workout_sets_title), TypographyTokens.TitleS)
            sets.forEachIndexed { i, r ->
                val a11y = stringResource(R.string.workout_set_a11y, i + 1, r.reps)
                Row(Modifier.fillMaxWidth().heightIn(min = 32.dp).semantics(mergeDescendants = true) { contentDescription = a11y },
                    verticalAlignment = Alignment.CenterVertically) {
                    TokenText(if (r.completed) "✓" else "○", TypographyTokens.TitleS,
                        color = (if (r.completed) ColorTokens.StateSuccessText else ColorTokens.TextTertiary).resolve())
                    TokenText(stringResource(R.string.workout_set_n, i + 1), TypographyTokens.BodyS, Modifier.weight(1f).padding(start = SpacingTokens.S),
                        color = ColorTokens.TextSecondary.resolve())
                    val kind = workout.sets.getOrNull(i)?.kind ?: SetKind.AMRAP
                    TokenText(if (kind == SetKind.REPS) "${r.reps} / ${r.target}" else r.reps.toString(), TypographyTokens.TitleS)
                }
            }
            val skipped = workout.sets.size - sets.size
            if (skipped > 0) {
                TokenText(stringResource(R.string.workout_skipped, skipped), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
            }
        }
    }
}
