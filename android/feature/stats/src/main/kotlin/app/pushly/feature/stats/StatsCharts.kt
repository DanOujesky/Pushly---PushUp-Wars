package app.pushly.feature.stats

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.background
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import app.pushly.core.designsystem.TokenText
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.MotionTokens
import app.pushly.core.designsystem.generated.SpacingTokens
import app.pushly.core.designsystem.generated.TokenColor
import app.pushly.core.designsystem.generated.TypographyTokens
import app.pushly.core.designsystem.resolve
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.math.sin

/** Badge colour per tier (bronze → diamond). */
internal fun tierColor(tier: Int): TokenColor = when (tier) {
    1 -> ColorTokens.LeagueBronze
    2 -> ColorTokens.LeagueSilver
    3 -> ColorTokens.LeagueGold
    4 -> ColorTokens.LeaguePlatinum
    else -> ColorTokens.LeagueDiamond
}

/** Entry animation (doc 10 §2: grow / draw in 600 ms); the system animator scale turns it off. */
@Composable
private fun rememberEntry(key: Any): Float {
    val anim = remember(key) { Animatable(0f) }
    LaunchedEffect(key) { anim.animateTo(1f, tween(MotionTokens.SLOW_MS)) }
    return anim.value
}

@Composable
private fun AxisRow(start: String, end: String) {
    Row(Modifier.fillMaxWidth().clearAndSetSemantics {}) {
        TokenText(start, TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
        Spacer(Modifier.weight(1f))
        TokenText(end, TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
    }
}

@Composable
private fun LegendDot(color: Color, label: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Xs)) {
        Box(Modifier.size(10.dp).background(color, RoundedCornerShape(3.dp)))
        TokenText(label, TypographyTokens.Caption, color = ColorTokens.TextSecondary.resolve())
    }
}

/** Chart 1 — daily push-ups stacked by context; tap or drag to read a bucket. */
@Composable
internal fun DailyBarsChart(bars: List<StatsSeries.Bar>, summary: String) {
    val wake = ColorTokens.BrandFlame.resolve()
    val battle = ColorTokens.BrandVolt.resolve()
    val training = ColorTokens.BrandCyan.resolve()
    val grid = ColorTokens.StrokeSubtle.resolve()
    val highlight = ColorTokens.TextPrimary.resolve().copy(alpha = 0.08f)
    val entry = rememberEntry(bars)
    var selected by remember(bars) { mutableStateOf<Int?>(null) }
    val maxTotal = max(bars.maxOfOrNull { it.total } ?: 0, 1)
    val pick = selected?.let { bars.getOrNull(it) }

    Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
        TokenText(
            if (pick != null) {
                stringResource(R.string.stats_bar_tooltip, pick.start, pick.total, pick.wake, pick.battle, pick.training)
            } else {
                stringResource(R.string.stats_bar_max, maxTotal)
            },
            TypographyTokens.Caption,
            color = ColorTokens.TextTertiary.resolve(),
        )
        Canvas(
            Modifier
                .fillMaxWidth()
                .height(200.dp)
                .pointerInput(bars) {
                    detectTapGestures { o -> selected = (o.x / size.width * bars.size).toInt().coerceIn(0, bars.size - 1) }
                }
                .pointerInput(bars) {
                    detectHorizontalDragGestures { change, _ ->
                        selected = (change.position.x / size.width * bars.size).toInt().coerceIn(0, bars.size - 1)
                    }
                }
                .semantics { contentDescription = summary },
        ) {
            for (i in 0..3) {
                val y = size.height * i / 3f
                drawLine(grid, Offset(0f, y), Offset(size.width, y), strokeWidth = 1f)
            }
            if (bars.isEmpty()) return@Canvas
            val slot = size.width / bars.size
            val barW = slot * 0.7f
            bars.forEachIndexed { i, b ->
                if (i == selected) drawRect(highlight, Offset(i * slot, 0f), Size(slot, size.height))
                var top = size.height
                val x = i * slot + (slot - barW) / 2
                listOf(b.wake to wake, b.battle to battle, b.training to training).forEach { (v, c) ->
                    if (v > 0) {
                        val h = size.height * v / maxTotal * entry
                        top -= h
                        drawRect(c, Offset(x, top), Size(barW, h))
                    }
                }
            }
        }
        AxisRow(bars.firstOrNull()?.start ?: "", bars.lastOrNull()?.start ?: "")
        Row(horizontalArrangement = Arrangement.spacedBy(SpacingTokens.M)) {
            LegendDot(wake, stringResource(R.string.stats_wake))
            LegendDot(battle, stringResource(R.string.stats_battle))
            LegendDot(training, stringResource(R.string.stats_training))
        }
    }
}

/** Chart 2 — cumulative push-ups with milestone markers. */
@Composable
internal fun CumulativeChart(points: List<StatsSeries.Point>, milestones: List<StatsSeries.Point>, summary: String) {
    val line = ColorTokens.BrandFlame.resolve()
    val lime = ColorTokens.BrandLime.resolve()
    val grid = ColorTokens.StrokeSubtle.resolve()
    val entry = rememberEntry(points)
    val maxV = max(points.maxOfOrNull { it.value } ?: 0, 1)
    val minV = points.minOfOrNull { it.value } ?: 0
    val first = points.firstOrNull()?.date?.let { runCatching { java.time.LocalDate.parse(it) }.getOrNull() }
    val last = points.lastOrNull()?.date?.let { runCatching { java.time.LocalDate.parse(it) }.getOrNull() }
    val span = if (first != null && last != null) max(java.time.temporal.ChronoUnit.DAYS.between(first, last), 1L) else 1L

    fun xOf(date: String, width: Float): Float {
        val d = runCatching { java.time.LocalDate.parse(date) }.getOrNull() ?: return 0f
        return if (first == null) 0f else width * java.time.temporal.ChronoUnit.DAYS.between(first, d) / span
    }

    Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
        TokenText(stringResource(R.string.stats_total_now, points.lastOrNull()?.value ?: 0), TypographyTokens.Caption,
            color = ColorTokens.TextTertiary.resolve())
        Canvas(Modifier.fillMaxWidth().height(180.dp).semantics { contentDescription = summary }) {
            for (i in 0..3) {
                val y = size.height * i / 3f
                drawLine(grid, Offset(0f, y), Offset(size.width, y), strokeWidth = 1f)
            }
            if (points.isEmpty()) return@Canvas
            val range = max(maxV - minV, 1)
            fun yOf(v: Int) = size.height - size.height * 0.9f * (v - minV) / range - size.height * 0.05f
            val path = Path()
            points.forEachIndexed { i, p ->
                val x = xOf(p.date, size.width) * entry
                if (i == 0) path.moveTo(x, yOf(p.value)) else path.lineTo(x, yOf(p.value))
            }
            val area = Path().apply {
                addPath(path)
                lineTo(xOf(points.last().date, size.width) * entry, size.height)
                lineTo(0f, size.height)
                close()
            }
            drawPath(area, Brush.verticalGradient(listOf(line.copy(alpha = 0.4f), line.copy(alpha = 0f))))
            drawPath(path, line, style = Stroke(width = 2.5.dp.toPx(), cap = StrokeCap.Round))
            milestones.forEach { m ->
                drawCircle(lime, radius = 5.dp.toPx(), center = Offset(xOf(m.date, size.width) * entry, yOf(m.value)))
            }
        }
        AxisRow(points.firstOrNull()?.date ?: "", points.lastOrNull()?.date ?: "")
        if (milestones.isNotEmpty()) {
            TokenText(
                stringResource(R.string.stats_milestones, milestones.joinToString { if (it.value >= 1000) "${it.value / 1000}k" else "${it.value}" }),
                TypographyTokens.Caption,
                color = lime,
            )
        }
    }
}

internal fun clock(minute: Double): String {
    val m = minute.roundToInt().mod(1440)
    return "%02d:%02d".format(m / 60, m % 60)
}

/** Chart 3 — wake consistency: alarm time (hollow ring, ±10 min band) vs. completion (filled dot, green / red). */
@Composable
internal fun WakeTimesChart(wakes: List<StatsData.Wake>, summary: String) {
    val ring = ColorTokens.TextTertiary.resolve()
    val band = ColorTokens.StrokeSubtle.resolve().copy(alpha = 0.6f)
    val ok = ColorTokens.StateSuccess.resolve()
    val bad = ColorTokens.StateDanger.resolve()
    val values = wakes.flatMap { listOfNotNull(it.scheduledMinute, it.completedMinute) }
    val low = (values.minOrNull() ?: 360.0) - 20
    val high = max((values.maxOrNull() ?: 480.0) + 20, low + 60)
    val entry = rememberEntry(wakes)

    Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
        Row {
            TokenText(clock(low), TypographyTokens.Caption, color = ring)
            Spacer(Modifier.weight(1f))
        }
        Canvas(Modifier.fillMaxWidth().height(180.dp).semantics { contentDescription = summary }) {
            if (wakes.isEmpty()) return@Canvas
            val slot = size.width / wakes.size
            fun yOf(m: Double) = (size.height * (m - low) / (high - low)).toFloat()   // earlier = higher
            wakes.forEachIndexed { i, w ->
                val cx = i * slot + slot / 2
                w.scheduledMinute?.let { s ->
                    drawRect(band, Offset(i * slot + slot * 0.1f, yOf(s - 10)), Size(slot * 0.8f, yOf(s + 10) - yOf(s - 10)))
                    drawCircle(ring, radius = 5.dp.toPx(), center = Offset(cx, yOf(s)), style = Stroke(width = 2.dp.toPx()))
                }
                val c = w.completedMinute
                if (c != null) {
                    drawCircle(if (w.status == "succeeded") ok else bad, radius = 5.dp.toPx() * entry, center = Offset(cx, yOf(c)))
                } else {
                    w.scheduledMinute?.let { s ->
                        val r = 5.dp.toPx()
                        drawLine(bad, Offset(cx - r, yOf(s) - r), Offset(cx + r, yOf(s) + r), strokeWidth = 2.dp.toPx())
                        drawLine(bad, Offset(cx - r, yOf(s) + r), Offset(cx + r, yOf(s) - r), strokeWidth = 2.dp.toPx())
                    }
                }
            }
        }
        Row {
            TokenText(clock(high), TypographyTokens.Caption, color = ring)
            Spacer(Modifier.weight(1f))
        }
        AxisRow(wakes.firstOrNull()?.date ?: "", wakes.lastOrNull()?.date ?: "")
    }
}

/** Chart 4 — best set per active day; gold stars mark records within the period. */
@Composable
internal fun BestSetChart(points: List<StatsSeries.Point>, summary: String) {
    val line = ColorTokens.BrandVolt.resolve()
    val gold = ColorTokens.LeagueGold.resolve()
    val entry = rememberEntry(points)
    val maxV = max(points.maxOfOrNull { it.value } ?: 0, 1)

    Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
        Canvas(Modifier.fillMaxWidth().height(160.dp).semantics { contentDescription = summary }) {
            if (points.isEmpty()) return@Canvas
            val step = if (points.size > 1) size.width / (points.size - 1) else 0f
            fun pos(i: Int, v: Int) = Offset(
                if (points.size > 1) i * step else size.width / 2,
                size.height - size.height * 0.85f * v / maxV * entry - size.height * 0.05f,
            )
            val path = Path()
            points.forEachIndexed { i, p ->
                val o = pos(i, p.value)
                if (i == 0) path.moveTo(o.x, o.y) else path.lineTo(o.x, o.y)
            }
            drawPath(path, line, style = Stroke(width = 2.5.dp.toPx(), cap = StrokeCap.Round))
            points.forEachIndexed { i, p ->
                val o = pos(i, p.value)
                if (p.isRecord) drawPath(star(o, 7.dp.toPx()), gold) else drawCircle(line, radius = 3.dp.toPx(), center = o)
            }
        }
        AxisRow(points.firstOrNull()?.date ?: "", points.lastOrNull()?.date ?: "")
    }
}

private fun star(center: Offset, r: Float): Path = Path().apply {
    for (k in 0 until 10) {
        val radius = if (k % 2 == 0) r else r * 0.45f
        val a = Math.PI / 5 * k - Math.PI / 2
        val p = Offset(center.x + (radius * cos(a)).toFloat(), center.y + (radius * sin(a)).toFloat())
        if (k == 0) moveTo(p.x, p.y) else lineTo(p.x, p.y)
    }
    close()
}

private val HEAT_STEPS = floatArrayOf(0.15f, 0.35f, 0.55f, 0.78f, 1f)

/** Chart 6 — activity heatmap for the last 53 weeks (5-step lime scale, doc 14 §1). */
@Composable
internal fun HeatmapChart(cells: List<StatsSeries.HeatCell>, summary: String) {
    val lime = ColorTokens.BrandLime.resolve()
    val weeks = (cells.maxOfOrNull { it.week } ?: 0) + 1
    Column(verticalArrangement = Arrangement.spacedBy(SpacingTokens.S)) {
        Canvas(Modifier.fillMaxWidth().height(96.dp).semantics { contentDescription = summary }) {
            val gap = 2f
            val side = minOf((size.width - gap * (weeks - 1)) / weeks, (size.height - gap * 6) / 7)
            cells.forEach { c ->
                drawRoundRect(
                    lime.copy(alpha = HEAT_STEPS[c.level.coerceIn(0, 4)]),
                    topLeft = Offset(c.week * (side + gap), c.weekday * (side + gap)),
                    size = Size(side, side),
                    cornerRadius = CornerRadius(side / 4),
                )
            }
        }
        Row(
            Modifier.clearAndSetSemantics {},
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(SpacingTokens.Xs),
        ) {
            TokenText(stringResource(R.string.stats_less), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
            HEAT_STEPS.forEach { Box(Modifier.size(10.dp).background(lime.copy(alpha = it), RoundedCornerShape(2.dp))) }
            TokenText(stringResource(R.string.stats_more), TypographyTokens.Caption, color = ColorTokens.TextTertiary.resolve())
        }
    }
}
