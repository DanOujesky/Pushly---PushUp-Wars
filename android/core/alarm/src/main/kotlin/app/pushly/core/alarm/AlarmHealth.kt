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
}
