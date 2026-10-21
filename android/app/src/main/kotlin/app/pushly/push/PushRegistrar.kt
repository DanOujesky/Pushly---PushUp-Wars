package app.pushly.push

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import app.pushly.BuildConfig
import app.pushly.R
import app.pushly.core.common.AccountService
import app.pushly.core.common.PLog
import app.pushly.feature.wakeflow.LogSigner
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.messaging.FirebaseMessaging
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

/**
 * Remote notifications (doc 15 §2, P6-06): Firebase is set up from build config (no google-services plugin; values from
 * `google-services.json` or CI secrets, docs/RELEASING.md), the FCM token goes to `register_push_token` for this
 * install's device row. Builds without the Firebase config simply have no push — alarms never depend on it.
 */
object PushRegistrar {
    const val CHANNEL_URGENT = "pushly_urgent"
    const val CHANNEL_ACTIVITY = "pushly_activity"

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    @Volatile private var target: Pair<AccountService, LogSigner>? = null
    @Volatile private var lastToken: String? = null

    val isConfigured: Boolean
        get() = BuildConfig.FIREBASE_APP_ID.isNotBlank() && BuildConfig.FIREBASE_API_KEY.isNotBlank() &&
            BuildConfig.FIREBASE_PROJECT_ID.isNotBlank()

    /** Process start: channels (the server sends to these ids) + Firebase when configured. */
    fun init(context: Context) {
        val nm = context.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_URGENT, context.getString(R.string.push_channel_urgent), NotificationManager.IMPORTANCE_HIGH),
        )
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ACTIVITY, context.getString(R.string.push_channel_activity), NotificationManager.IMPORTANCE_DEFAULT),
        )
        if (!isConfigured || FirebaseApp.getApps(context).isNotEmpty()) return
        try {
            val options = FirebaseOptions.Builder()
                .setApplicationId(BuildConfig.FIREBASE_APP_ID)
                .setApiKey(BuildConfig.FIREBASE_API_KEY)
                .setProjectId(BuildConfig.FIREBASE_PROJECT_ID)
                .setGcmSenderId(BuildConfig.FIREBASE_SENDER_ID)
                .build()
            FirebaseApp.initializeApp(context, options)
        } catch (e: Exception) {
            PLog.warning(PLog.Category.Sync) { "Firebase init failed: ${e.message}" }
        }
    }

    /** Signed in: register the current token (and later ones from [onNewToken]). */
    fun register(account: AccountService, signer: LogSigner) {
        target = account to signer
        if (!isConfigured) return
        scope.launch {
            val token = currentToken() ?: return@launch
            send(token)
        }
    }

    /** Signed out: stop sending new tokens for this account. */
    fun clear() {
        target = null
        lastToken = null
    }

    fun onNewToken(token: String) {
        scope.launch { send(token) }
    }

    private suspend fun currentToken(): String? = try {
        suspendCancellableCoroutine { cont ->
            FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                cont.resume(if (task.isSuccessful) task.result else null)
            }
        }
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        PLog.warning(PLog.Category.Sync) { "FCM token unavailable: ${e.message}" }
        null
    }

    private suspend fun send(token: String) {
        val (account, signer) = target ?: return
        if (token == lastToken) return
        try {
            val deviceId = signer.deviceId() ?: return
            account.registerPushToken(deviceId, token)
            lastToken = token
            PLog.info(PLog.Category.Sync) { "Push token registered" }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            PLog.warning(PLog.Category.Sync) { "Push token not registered: ${e.message}" }
        }
    }
}
