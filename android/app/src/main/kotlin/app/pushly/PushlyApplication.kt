package app.pushly

import android.app.Application
import android.util.Log
import app.pushly.core.alarm.AlarmLog
import app.pushly.core.common.AppActivity
import app.pushly.core.common.PLog
import app.pushly.feature.shop.AdHistory
import app.pushly.feature.shop.Shop
import app.pushly.feature.shop.ShopConfig
import app.pushly.feature.alarm.AlarmIntegrityWorker
import app.pushly.feature.alarm.AlarmNotifications
import app.pushly.feature.alarm.AlarmSystem
import app.pushly.feature.wakeflow.SessionServices
import app.pushly.feature.wakeflow.SessionUploader
import app.pushly.push.PushRegistrar
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import java.io.File

/**
 * Process start: logging first (receivers and the ring service run without any activity), then alarm housekeeping.
 * Alarms are re-armed on every process start — cheap, idempotent and the best defence against lost alarms.
 */
class PushlyApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        PLog.debugEnabled = BuildConfig.DEBUG
        PLog.sink = PLog.Sink { level, category, message ->
            val tag = "Pushly/${category.name}"
            when (level) {
                PLog.Level.Debug -> Log.d(tag, message)
                PLog.Level.Info -> Log.i(tag, message)
                PLog.Level.Warning -> Log.w(tag, message)
                PLog.Level.Error -> Log.e(tag, message)
            }
        }
        AlarmLog.sink = { message -> PLog.warning(PLog.Category.Alarm) { message } }
        AlarmNotifications.ensureChannels(this)
        PushRegistrar.init(this)
        AlarmSystem.get(this).scheduler.sync()
        AlarmIntegrityWorker.ensureScheduled(this)
        // Rep-log outbox (P4-05): queued offline / in guest mode, uploaded while signed in (transport set by MainActivity).
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        // Ads + Pushly Pro (D-073): counters for the AdsGate, the shop with build-time IDs (Google test IDs by default).
        val ads = getSharedPreferences("pushly.ads", MODE_PRIVATE)
        AppActivity.store = object : AppActivity.Store {
            override fun getInt(key: String): Int = ads.getInt(key, 0)
            override fun putInt(key: String, value: Int) {
                ads.edit().putInt(key, value).apply()
            }
        }
        PushlyShop.shared = Shop(
            this,
            ShopConfig.of(BuildConfig.ADMOB_BANNER_ID, BuildConfig.ADMOB_INTERSTITIAL_ID, BuildConfig.REVENUECAT_ANDROID_KEY),
            AdHistory({ ads.getString("shown", null) }, { ads.edit().putString("shown", it).apply() }),
        ).also { it.install() }
        SessionServices.shared = SessionServices(
            SessionUploader(File(filesDir, "RepSessions"), scope),
            "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})",
        )
    }
}

/** The app-wide ads + Pushly Pro shop (created at process start). */
object PushlyShop {
    @Volatile var shared: Shop? = null
}
