package app.pushly.core.alarm

/** Everything the health check needs, read from the OS by the platform layer. null = not applicable on this platform. */
data class HealthInput(
    val hasEnabledAlarms: Boolean,
    val alarmKitAuthorized: Boolean? = null,
    val exactAlarmAllowed: Boolean? = null,
    val fullScreenIntentAllowed: Boolean? = null,
    val notificationsAllowed: Boolean? = null,
    val alarmChannelOk: Boolean? = null,
    val batteryRestrictedOnAggressiveOem: Boolean? = null,
    val cameraDenied: Boolean = false,
    val nextAlarmArmed: Boolean? = null,
    val alarmVolumeZero: Boolean? = null,
    val customSoundMissing: Boolean = false,
)

enum class HealthSeverity { Critical, Warning }

/** Alarm health issues (doc 04 §8). Codes are identical on iOS. */
enum class HealthIssue(val code: String, val severity: HealthSeverity) {
    AlarmKitNotAuthorized("alarmKitNotAuthorized", HealthSeverity.Critical),
    ExactAlarmMissing("exactAlarmMissing", HealthSeverity.Critical),
    FullScreenIntentMissing("fullScreenIntentMissing", HealthSeverity.Critical),
    NotificationsBlocked("notificationsBlocked", HealthSeverity.Critical),
    AlarmChannelMuted("alarmChannelMuted", HealthSeverity.Critical),
    CameraDenied("cameraDenied", HealthSeverity.Critical),
    NextAlarmNotArmed("nextAlarmNotArmed", HealthSeverity.Critical),
    BatteryRestricted("batteryRestricted", HealthSeverity.Warning),
    AlarmVolumeZero("alarmVolumeZero", HealthSeverity.Warning),
    CustomSoundMissing("customSoundMissing", HealthSeverity.Warning),
}

object AlarmHealth {
    /** Issues in display order (critical first, then table order). No alarms → nothing to warn about. */
    fun issues(i: HealthInput): List<HealthIssue> {
        if (!i.hasEnabledAlarms) return emptyList()
        val out = ArrayList<HealthIssue>()
        if (i.alarmKitAuthorized == false) out += HealthIssue.AlarmKitNotAuthorized
        if (i.exactAlarmAllowed == false) out += HealthIssue.ExactAlarmMissing
        if (i.fullScreenIntentAllowed == false) out += HealthIssue.FullScreenIntentMissing
        if (i.notificationsAllowed == false) out += HealthIssue.NotificationsBlocked
        if (i.alarmChannelOk == false) out += HealthIssue.AlarmChannelMuted
        if (i.cameraDenied) out += HealthIssue.CameraDenied
        // Only meaningful when the OS lets us schedule at all; otherwise the permission issue explains it.
        if (i.nextAlarmArmed == false && out.isEmpty()) out += HealthIssue.NextAlarmNotArmed
        if (i.batteryRestrictedOnAggressiveOem == true) out += HealthIssue.BatteryRestricted
        if (i.alarmVolumeZero == true) out += HealthIssue.AlarmVolumeZero
        if (i.customSoundMissing) out += HealthIssue.CustomSoundMissing
        return out.sortedBy { it.severity.ordinal }
    }

    /** Local hour of the evening health reminder (doc 04 §8). */
    const val REMINDER_HOUR = 21

    /**
     * When to show the evening reminder: the next 21:00 local, but only if a critical issue exists and an alarm is due
     * within 24 h of that moment. null = no reminder. Same rule as iOS `AlarmHealth.eveningReminder`.
     */
    fun eveningReminder(critical: Boolean, nextAlarm: java.time.Instant?, now: java.time.Instant, zone: java.time.ZoneId): java.time.Instant? {
        if (!critical || nextAlarm == null) return null
        val today = now.atZone(zone).toLocalDate()
        var at = today.atTime(REMINDER_HOUR, 0).atZone(zone).toInstant()
        if (!at.isAfter(now)) at = today.plusDays(1).atTime(REMINDER_HOUR, 0).atZone(zone).toInstant()
        if (!nextAlarm.isAfter(at) || java.time.Duration.between(at, nextAlarm) > java.time.Duration.ofHours(24)) return null
        return at
    }
}
