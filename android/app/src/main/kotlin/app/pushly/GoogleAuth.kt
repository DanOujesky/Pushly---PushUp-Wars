package app.pushly

import android.content.Context
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import app.pushly.core.common.PLog
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential

/**
 * Native Google sign-in via Credential Manager (D-061): the ID token's audience is the web client ID that Supabase
 * accepts. Works only once the Android OAuth client (package + SHA-1 of the Play signing key) exists in Google Cloud,
 * so the button stays hidden until `GOOGLE_SIGN_IN_ANDROID=true` (local.properties / CI env).
 */
object GoogleAuth {
    val isEnabled: Boolean get() = BuildConfig.GOOGLE_SIGN_IN_ANDROID && BuildConfig.GOOGLE_WEB_CLIENT_ID.isNotBlank()

    /** The ID token, or null when the user closes the sheet. Needs an Activity context for the UI. */
    suspend fun signIn(context: Context): String? {
        val option = GetSignInWithGoogleOption.Builder(BuildConfig.GOOGLE_WEB_CLIENT_ID).build()
        val request = GetCredentialRequest.Builder().addCredentialOption(option).build()
        return try {
            val credential = CredentialManager.create(context).getCredential(context, request).credential
            if (credential is CustomCredential && credential.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) {
                GoogleIdTokenCredential.createFrom(credential.data).idToken
            } else {
                PLog.warning { "Unexpected credential type ${credential.type}" }
                null
            }
        } catch (e: GetCredentialCancellationException) {
            null
        }
    }
}
