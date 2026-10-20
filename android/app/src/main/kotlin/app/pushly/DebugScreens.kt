package app.pushly

import android.content.Context
import android.content.Intent
import app.pushly.core.alarm.AlarmSchedule
import app.pushly.core.alarm.AlarmSound
import app.pushly.core.alarm.ChallengeMode
import app.pushly.core.alarm.ModeType
import app.pushly.core.alarm.WeeklyTimes
import app.pushly.core.common.Profile
import app.pushly.feature.alarm.AlarmSystem
import app.pushly.feature.alarm.WakeDebug

/**
 * Debug builds only (called behind `BuildConfig.DEBUG`): opens a fixed screen for the emulator screenshot job
 * (`.github/workflows/android-screens.yml`):
 * `adb shell am start -n app.pushly.debug/app.pushly.MainActivity --es debugScreen ring`
 */
object DebugScreens {
    fun apply(context: Context, intent: Intent, session: AppSession, router: AppRouter) {
        val screen = intent.getStringExtra("debugScreen") ?: return
        val profile = Profile(
            id = "00000000-0000-4000-8000-000000000001",
            username = "DanPushes",
            onboardingCompleted = true,
            avatarPreset = "preset.flame",
            trophies = 640,
            level = 7,
        )
        session.debugStartState = when (screen) {
            "welcome" -> AppSession.State.Welcome
            "signIn" -> AppSession.State.SignIn
            "profileSetup" -> AppSession.State.ProfileSetup(profile.copy(username = "u_0123456789ab", onboardingCompleted = false))
            "update" -> AppSession.State.UpdateRequired
            "launch" -> AppSession.State.Launching
            else -> AppSession.State.Main(profile)
        }
        if (screen in setOf("wake", "editor", "permissions", "ring", "emptyWake")) {
            router.select(AppTab.Wake)
            if (screen != "emptyWake") seed(context)
            WakeDebug.initialRoute = screen.takeIf { it == "editor" || it == "permissions" }
        }
        if (screen == "profile") router.select(AppTab.Profile)
        if (screen == "ring") {
            val system = AlarmSystem.get(context)
            system.repository.alarms.value.firstOrNull()?.let { system.scheduler.armPractice(it, delaySeconds = 3) }
        }
    }

    private fun seed(context: Context) {
        val system = AlarmSystem.get(context)
        val repo = system.repository
        if (repo.alarms.value.isNotEmpty()) return
        repo.save(
            AlarmSchedule.newDefault("d0000000-0000-4000-8000-000000000001").copy(
                label = "Get up, champion",
                weekly = WeeklyTimes(mon = "06:30", tue = "06:30", wed = "06:30", thu = "06:30", fri = "06:30"),
            ),
        )
        repo.save(
            AlarmSchedule.newDefault("d0000000-0000-4000-8000-000000000002").copy(
                label = "Weekend",
                weekly = WeeklyTimes(sat = "09:00", sun = "09:30"),
                mode = ChallengeMode.defaults(ModeType.Escalation, targetReps = 15),
                sound = AlarmSound("bundled.arena"),
            ),
        )
        system.scheduler.sync()
    }
}
