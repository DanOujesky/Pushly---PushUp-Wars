package app.pushly.push

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import app.pushly.MainActivity
import app.pushly.core.common.PLog
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * FCM callbacks. In the background the system shows notification messages itself (tap → MainActivity with the `link`
 * extra); in the foreground we post the same notification so nothing is lost.
 */
class PushlyMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) = PushRegistrar.onNewToken(token)

    @SuppressLint("MissingPermission") // checked with areNotificationsEnabled(); SecurityException caught below
    override fun onMessageReceived(message: RemoteMessage) {
        val title = message.notification?.title ?: message.data["title"] ?: return
        val body = message.notification?.body ?: message.data["body"].orEmpty()
        val manager = NotificationManagerCompat.from(this)
        if (!manager.areNotificationsEnabled()) return
        val open = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra("link", message.data["link"])
        val pending = PendingIntent.getActivity(this, title.hashCode(), open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val channel = message.notification?.channelId ?: PushRegistrar.CHANNEL_ACTIVITY
        val notification = NotificationCompat.Builder(this, channel)
            .setSmallIcon(app.pushly.feature.alarm.R.drawable.ic_stat_alarm)
            .setContentTitle(title)
            .setContentText(body)
            .setAutoCancel(true)
            .setContentIntent(pending)
            .build()
        try {
            manager.notify(message.messageId?.hashCode() ?: title.hashCode(), notification)
        } catch (e: SecurityException) {
            PLog.warning(PLog.Category.Sync) { "Notification not shown: ${e.message}" }
        }
    }
}
