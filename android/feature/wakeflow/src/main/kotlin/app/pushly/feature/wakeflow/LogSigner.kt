package app.pushly.feature.wakeflow

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import app.pushly.core.common.PLog
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.Signature
import java.security.spec.ECGenParameterSpec
import java.util.Base64

/** This install's signing key (doc 06 §3) — P-256, SHA-256; the private key never leaves the device. */
interface DeviceKey {
    /** SubjectPublicKeyInfo DER — what `register_device` stores and the server verifies with. */
    val publicKeySpki: ByteArray

    /** ECDSA signature (DER) over [data]. */
    fun sign(data: ByteArray): ByteArray
}

/** Android Keystore key (hardware-backed where the phone supports it). */
class KeystoreDeviceKey private constructor(private val privateKey: PrivateKey, override val publicKeySpki: ByteArray) : DeviceKey {
    override fun sign(data: ByteArray): ByteArray = Signature.getInstance("SHA256withECDSA").run {
        initSign(privateKey)
        update(data)
        sign()
    }

    companion object {
        private const val ALIAS = "app.pushly.devicekey"

        fun loadOrCreate(): KeystoreDeviceKey? = try {
            val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            if (!ks.containsAlias(ALIAS)) {
                KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore").apply {
                    initialize(
                        KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_SIGN)
                            .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                            .setDigests(KeyProperties.DIGEST_SHA256)
                            .build(),
                    )
                    generateKeyPair()
                }
            }
            val entry = ks.getEntry(ALIAS, null) as KeyStore.PrivateKeyEntry
            KeystoreDeviceKey(entry.privateKey, entry.certificate.publicKey.encoded)
        } catch (e: java.security.GeneralSecurityException) {
            PLog.warning(PLog.Category.Sync) { "Device key unavailable: ${e.message}" }
            null
        } catch (e: java.io.IOException) {
            PLog.warning(PLog.Category.Sync) { "Device key unavailable: ${e.message}" }
            null
        }
    }
}

/**
 * Wraps rep logs in the signed envelope `{log, signature, deviceId}` (D-047). Registers the device key once per
 * launch (idempotent on the server). Any failure falls back to the bare log, which the server accepts with a soft
 * flag — signing must never block an upload. Same behaviour as iOS `LogSigner`.
 */
class LogSigner(
    private val key: DeviceKey?,
    private val appVersion: String,
    private val register: suspend (String) -> String,
) {
    private val mutex = Mutex()
    @Volatile private var deviceId: String? = null

    suspend fun envelope(log: String): String {
        val k = key ?: return log
        return try {
            val id = registeredId(k)
            val signature = Base64.getEncoder().encodeToString(k.sign(log.encodeToByteArray()))
            buildJsonObject {
                put("log", log)
                put("signature", signature)
                put("deviceId", id)
            }.toString()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            PLog.warning(PLog.Category.Sync) { "Rep log sent unsigned: ${e.message}" }
            log
        }
    }

    /** This install's device row id (registers the key if needed) — also used for the push token. */
    suspend fun deviceId(): String? = key?.let { registeredId(it) }

    private suspend fun registeredId(k: DeviceKey): String = mutex.withLock {
        deviceId ?: register(
            buildJsonObject {
                put("platform", "android")
                put("publicKey", Base64.getEncoder().encodeToString(k.publicKeySpki))
                put("model", ((Build.MANUFACTURER ?: "") + " " + (Build.MODEL ?: "")).trim())
                put("osVersion", Build.VERSION.RELEASE ?: "")
                put("appVersion", appVersion)
            }.toString(),
        ).also { deviceId = it }
    }
}
