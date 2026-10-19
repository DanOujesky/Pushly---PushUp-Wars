package app.pushly.feature.alarm

import android.Manifest
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import app.pushly.core.alarm.AlarmHealth
import app.pushly.core.alarm.HealthInput
import app.pushly.core.alarm.HealthIssue

/** Reads the OS state the alarm depends on and opens the right settings screen to fix it (doc 04 §6.1, §8). */
object AlarmPermissions {
    /** Steps shown on the permission explainer, in order. */
    enum class Step { Notifications, ExactAlarms, FullScreen, Battery }

    private val aggressiveOems = setOf("xiaomi", "redmi", "poco", "huawei", "honor", "oppo", "realme", "vivo", "oneplus", "samsung")

    fun notificationsAllowed(context: Context): Boolean {
        val runtime = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        return runtime && context.getSystemService(NotificationManager::class.java).areNotificationsEnabled()
    }

    fun exactAlarmsAllowed(context: Context): Boolean = AlarmSystem.get(context).scheduler.canScheduleExact()

    fun fullScreenAllowed(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE ||
            context.getSystemService(NotificationManager::class.java).canUseFullScreenIntent()

    fun isAggressiveOem(): Boolean = Build.MANUFACTURER.lowercase() in aggressiveOems

    fun batteryUnrestricted(context: Context): Boolean =
        context.getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(context.packageName)

    fun alarmVolumeZero(context: Context): Boolean =
        context.getSystemService(AudioManager::class.java).getStreamVolume(AudioManager.STREAM_ALARM) == 0

    fun isGranted(context: Context, step: Step): Boolean = when (step) {
        Step.Notifications -> notificationsAllowed(context)
        Step.ExactAlarms -> exactAlarmsAllowed(context)
        Step.FullScreen -> fullScreenAllowed(context)
        Step.Battery -> !isAggressiveOem() || batteryUnrestricted(context)
    }

    /** Steps that apply on this device (battery only on OEMs known to kill alarms). */
    fun steps(): List<Step> = buildList {
        add(Step.Notifications)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) add(Step.ExactAlarms)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) add(Step.FullScreen)
        if (isAggressiveOem()) add(Step.Battery)
    }

    fun missingRequired(context: Context): List<Step> = steps().filter { it != Step.Battery && !isGranted(context, it) }

    /** Settings screen that fixes a step (notifications on Android 13+ are a runtime dialog, handled by the caller). */
    fun settingsIntent(context: Context, step: Step): Intent {
        val pkg = Uri.parse("package:${context.packageName}")
        return when (step) {
            Step.Notifications -> Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            Step.ExactAlarms -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, pkg)
            } else {
                appDetails(pkg)
            }
            Step.FullScreen -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, pkg)
            } else {
                appDetails(pkg)
            }
            @Suppress("BatteryLife")
            Step.Battery -> Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, pkg)
        }.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    fun intentFor(context: Context, issue: HealthIssue): Intent = when (issue) {
        HealthIssue.ExactAlarmMissing -> settingsIntent(context, Step.ExactAlarms)
        HealthIssue.FullScreenIntentMissing -> settingsIntent(context, Step.FullScreen)
        HealthIssue.NotificationsBlocked -> settingsIntent(context, Step.Notifications)
        HealthIssue.AlarmChannelMuted -> Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            .putExtra(Settings.EXTRA_CHANNEL_ID, AlarmNotifications.CHANNEL_RING)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        HealthIssue.BatteryRestricted -> settingsIntent(context, Step.Battery)
        HealthIssue.AlarmVolumeZero -> Intent(Settings.ACTION_SOUND_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        else -> appDetails(Uri.parse("package:${context.packageName}")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    private fun appDetails(pkg: Uri) = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, pkg)

    /** Health check inputs from the OS (doc 04 §8). */
    fun health(context: Context): List<HealthIssue> {
        val system = AlarmSystem.get(context)
        val hasEnabled = system.repository.alarms.value.any { it.enabled }
        return AlarmHealth.issues(
            HealthInput(
                hasEnabledAlarms = hasEnabled,
                exactAlarmAllowed = exactAlarmsAllowed(context),
                fullScreenIntentAllowed = fullScreenAllowed(context),
                notificationsAllowed = notificationsAllowed(context),
                alarmChannelOk = AlarmNotifications.channelOk(context),
                batteryRestrictedOnAggressiveOem = isAggressiveOem() && !batteryUnrestricted(context),
                nextAlarmArmed = system.scheduler.nextAlarmArmed(),
                alarmVolumeZero = alarmVolumeZero(context),
            ),
        )
    }
}
