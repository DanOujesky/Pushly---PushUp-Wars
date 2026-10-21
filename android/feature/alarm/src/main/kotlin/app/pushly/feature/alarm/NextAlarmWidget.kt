package app.pushly.feature.alarm

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.updateAll
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import app.pushly.core.alarm.WakeSummary
import app.pushly.core.alarm.WidgetSnapshot
import app.pushly.core.common.PLog
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.RadiusTokens
import app.pushly.core.designsystem.generated.SpacingTokens
import app.pushly.core.designsystem.generated.TokenColor
import app.pushly.core.designsystem.generated.TypeToken
import app.pushly.core.designsystem.generated.TypographyTokens
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.temporal.ChronoUnit

/**
 * "Next alarm + streak" home screen widget (P6-07). Reads the local alarm schedules directly (same process) and the
 * last known streak / push-ups today; never touches the network. Same content as the iOS widget.
 */
class NextAlarmWidget : GlanceAppWidget() {
    override val sizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val snapshot = WidgetData.snapshot(context)
        provideContent { GlanceTheme { NextAlarmContent(context, snapshot) } }
    }
}

class NextAlarmWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = NextAlarmWidget()
}

/** Last known streak / push-ups today (device-protected prefs) + refresh of all widget instances. */
object WidgetData {
    private const val PREFS = "pushly.widget"

    private fun prefs(context: Context) =
        context.createDeviceProtectedStorageContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun snapshot(context: Context, now: Instant = Instant.now()): WidgetSnapshot {
        val p = prefs(context)
        val alarms = AlarmSystem.get(context).repository.alarms.value
        return WidgetSnapshot(
            upcoming = WidgetSnapshot.upcoming(alarms, now, ZoneId.systemDefault()),
            streak = if (p.contains("streak")) p.getInt("streak", 0) else null,
            repsToday = if (p.contains("repsToday")) p.getInt("repsToday", 0) else null,
            today = p.getString("today", null),
        )
    }

    fun saveSummary(context: Context, summary: WakeSummary) {
        val editor = prefs(context).edit().putInt("streak", summary.streak.current).putString("today", summary.today)
        val reps = summary.repsToday
        if (reps != null) editor.putInt("repsToday", reps) else editor.remove("repsToday")
        editor.apply()
    }

    suspend fun refresh(context: Context) {
        try {
            NextAlarmWidget().updateAll(context)
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            PLog.warning(PLog.Category.Alarm) { "Widget refresh failed: ${e.message}" }
        }
    }
}

private fun color(token: TokenColor) = ColorProvider(token.dark)

private fun style(token: TypeToken, color: TokenColor, bold: Boolean = false) =
    TextStyle(color = color(color), fontSize = token.size, fontWeight = if (bold) FontWeight.Bold else FontWeight.Normal)

@androidx.compose.runtime.Composable
private fun NextAlarmContent(context: Context, snapshot: WidgetSnapshot) {
    val now = Instant.now()
    val zone = ZoneId.systemDefault()
    val ring = snapshot.next(now)
    val streak = snapshot.streak ?: 0
    val open = Intent(Intent.ACTION_VIEW, Uri.parse("pushly://wake")).setPackage(context.packageName)
    Row(
        GlanceModifier.fillMaxSize().background(color(ColorTokens.BgBase)).cornerRadius(RadiusTokens.L)
            .padding(SpacingTokens.M).clickable(actionStartActivity(open)),
    ) {
        Column(GlanceModifier.defaultWeight()) {
            Text(context.getString(R.string.widget_next_alarm), style = style(TypographyTokens.Overline, ColorTokens.BrandFlameText, bold = true))
            if (ring != null) {
                val local = ring.at.atZone(zone)
                Text(DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).format(local),
                    style = style(TypographyTokens.DisplayM, ColorTokens.TextPrimary, bold = true))
                val days = ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), local.toLocalDate())
                val day = when (days) {
                    0L -> context.getString(R.string.widget_today)
                    1L -> context.getString(R.string.widget_tomorrow)
                    else -> local.dayOfWeek.getDisplayName(java.time.format.TextStyle.FULL, java.util.Locale.getDefault())
                }
                val target = ring.targetReps?.let { " · " + context.getString(R.string.widget_pushups, it) }.orEmpty()
                Text(day + target, style = style(TypographyTokens.Caption, ColorTokens.TextSecondary))
            } else {
                Text(context.getString(R.string.widget_no_alarm), style = style(TypographyTokens.TitleS, ColorTokens.TextPrimary, bold = true))
            }
            Spacer(GlanceModifier.defaultWeight())
            Text("🔥 $streak", style = style(TypographyTokens.LabelDisplay, if (streak > 0) ColorTokens.BrandFlameText else ColorTokens.TextTertiary, bold = true))
        }
        val reps = snapshot.repsToday(now, zone)
        if (reps != null) {
            Spacer(GlanceModifier.width(SpacingTokens.M))
            Column(verticalAlignment = Alignment.Top) {
                Text(context.getString(R.string.widget_today_caps), style = style(TypographyTokens.Overline, ColorTokens.BrandVoltText, bold = true))
                Text("$reps", style = style(TypographyTokens.DisplayM, ColorTokens.TextPrimary, bold = true))
                Text(context.getString(R.string.widget_pushups_word), style = style(TypographyTokens.Caption, ColorTokens.TextSecondary))
            }
        }
    }
}
