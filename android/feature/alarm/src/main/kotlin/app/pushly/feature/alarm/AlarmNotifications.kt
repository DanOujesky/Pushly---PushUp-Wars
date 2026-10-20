package app.pushly.feature.alarm

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import app.pushly.core.alarm.RingState
import app.pushly.core.common.PLog

/** Notification channel + the ringing notification with its full-screen intent (doc 04 §6.3). */
object AlarmNotifications {
    const val CHANNEL_RING = "alarm_ring"
    const val RING_NOTIFICATION_ID = 4201
    private const val FALLBACK_NOTIFICATION_ID = 4202
    const val CHANNEL_HEALTH = "alarm_health"
    private const val HEALTH_NOTIFICATION_ID = 4203

    fun ensureChannels(context: Context) {
        val nm = context.getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(CHANNEL_RING) != null) return
        val channel = NotificationChannel(CHANNEL_RING, context.getString(R.string.alarm_channel_name), NotificationManager.IMPORTANCE_HIGH).apply {
            description = context.getString(R.string.alarm_channel_description)
            setSound(null, null) // the ring service plays the alarm sound itself on the alarm stream
            enableVibration(false) // the service vibrates with the alarm pattern
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            setBypassDnd(true)
        }
        nm.createNotificationChannel(channel)
    }

    /** False when the user muted or lowered the alarm channel (health check §8). */
    fun channelOk(context: Context): Boolean {
        ensureChannels(context)
        val channel = context.getSystemService(NotificationManager::class.java).getNotificationChannel(CHANNEL_RING)
        return channel == null || channel.importance >= NotificationManager.IMPORTANCE_HIGH
    }

    fun ringNotification(context: Context, ring: RingState): Notification {
        ensureChannels(context)
        val fullScreen = PendingIntent.getActivity(
            context,
            1,
            Intent(context, RingActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_USER_ACTION),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val start = PendingIntent.getActivity(
            context,
            2,
            Intent(context, WakeActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val title = ring.label.ifBlank { context.getString(R.string.ring_default_title) }
        return NotificationCompat.Builder(context, CHANNEL_RING)
            .setSmallIcon(R.drawable.ic_stat_alarm)
            .setContentTitle(title)
            .setContentText(context.getString(R.string.ring_notification_text, ring.target))
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setFullScreenIntent(fullScreen, true)
            .setContentIntent(fullScreen)
            .addAction(0, context.getString(R.string.ring_start_pushups), start)
            .build()
    }

    /** Last resort if the ring service could not start: a loud, visible notification instead of silence. */
    fun showRingFallback(context: Context, alarmId: String?) {
        ensureChannels(context)
        val open = PendingIntent.getActivity(
            context,
            3,
            Intent(context, RingActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val n = NotificationCompat.Builder(context, CHANNEL_RING)
            .setSmallIcon(R.drawable.ic_stat_alarm)
            .setContentTitle(context.getString(R.string.ring_default_title))
            .setContentText(context.getString(R.string.ring_fallback_text))
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setFullScreenIntent(open, true)
            .setContentIntent(open)
            .build()
        PLog.warning(PLog.Category.Alarm) { "Showing fallback ring notification for alarm $alarmId" }
        runCatching { context.getSystemService(NotificationManager::class.java).notify(FALLBACK_NOTIFICATION_ID, n) }
    }

    /** "Your alarm may not ring" — evening reminder (doc 04 §8). */
    fun showHealthReminder(context: Context) {
        val nm = context.getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(CHANNEL_HEALTH) == null) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_HEALTH, context.getString(R.string.health_channel_name), NotificationManager.IMPORTANCE_DEFAULT),
            )
        }
        val open = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?.let { PendingIntent.getActivity(context, 4, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT) }
        val n = NotificationCompat.Builder(context, CHANNEL_HEALTH)
            .setSmallIcon(R.drawable.ic_stat_alarm)
            .setContentTitle(context.getString(R.string.health_reminder_title))
            .setContentText(context.getString(R.string.health_reminder_text))
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        runCatching { nm.notify(HEALTH_NOTIFICATION_ID, n) }
    }
}
