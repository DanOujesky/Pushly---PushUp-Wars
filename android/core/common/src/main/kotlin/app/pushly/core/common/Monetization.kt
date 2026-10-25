package app.pushly.core.common

import java.util.concurrent.ConcurrentHashMap

/**
 * What the user is doing right now, as far as ads care (doc 13 §1, CLAUDE.md §4.5). Features set these; the shop
 * module reads them into an [AdsGate.Context] before every ad. Same as iOS `AppActivity`. Counters persist through
 * [store] (the app plugs in SharedPreferences; tests use the in-memory default).
 */
object AppActivity {
    interface Store {
        fun getInt(key: String): Int
        fun putInt(key: String, value: Int)
    }

    private object InMemory : Store {
        private val map = ConcurrentHashMap<String, Int>()
        override fun getInt(key: String): Int = map[key] ?: 0
        override fun putInt(key: String, value: Int) {
            map[key] = value
        }
    }

    @Volatile var store: Store = InMemory

    /** A wake flow (alarm ringing → push-ups) is in progress. */
    @Volatile var wakeActive: Boolean = false
        private set

    /** When the last wake flow ended (epoch ms) — no ads for 10 minutes after it. */
    @Volatile var lastWakeEndedMs: Long? = null
        private set

    /** A camera session (wake, training, workout, battle) is on screen. */
    @Volatile var cameraActive: Boolean = false

    /** none | matchmaking | lobby | live | results */
    @Volatile var battlePhase: String = "none"

    private const val SESSIONS = "ads.completedSessions"
    private const val BATTLES = "ads.battlesSinceInterstitial"

    fun wakeStarted() {
        wakeActive = true
    }

    fun wakeEnded(nowMs: Long = System.currentTimeMillis()) {
        wakeActive = false
        lastWakeEndedMs = nowMs
    }

    /** Finished camera sessions on this device — no ads until the user has done 2 (new-user grace). */
    val completedSessions: Int get() = store.getInt(SESSIONS)

    fun sessionCompleted() = store.putInt(SESSIONS, completedSessions + 1)

    /** Battles since the last results interstitial (1 per 3 battles). */
    val battlesSinceInterstitial: Int get() = store.getInt(BATTLES)

    fun battleFinished() = store.putInt(BATTLES, battlesSinceInterstitial + 1)

    fun interstitialShown() = store.putInt(BATTLES, 0)
}

/**
 * Hooks between the features and the shop module (ads + Pushly Pro, doc 13). The app sets the handlers at launch;
 * features only call them, so they don't link the ad / purchase SDKs. Same as iOS `Monetization`.
 */
object Monetization {
    /** The user closed a battle's result screen — the only moment a results interstitial may show. */
    @Volatile var battleClosed: () -> Unit = {}

    /** Open the Pushly Pro paywall. Reason: profile | remove_ads | ghost_limit. */
    @Volatile var showPaywall: (String) -> Unit = {}

    private val _pro = kotlinx.coroutines.flow.MutableStateFlow(false)

    /** Pro as a flow, for screens with locked Pro items (D-074). */
    val pro: kotlinx.coroutines.flow.StateFlow<Boolean> get() = _pro

    private val _frame = kotlinx.coroutines.flow.MutableStateFlow<String?>(null)

    /** My chosen Pro frame (D-074), from my profile; draw it only while [pro] is true. */
    val frame: kotlinx.coroutines.flow.StateFlow<String?> get() = _frame

    fun setFrame(id: String?) {
        _frame.value = id
    }

    /** True while the user has Pushly Pro (store or server) — kept up to date by the shop module. */
    var isPro: Boolean
        get() = _pro.value
        set(value) {
            _pro.value = value
        }
}
