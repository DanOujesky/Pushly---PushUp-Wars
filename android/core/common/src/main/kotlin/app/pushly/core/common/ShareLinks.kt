package app.pushly.core.common

import java.net.URLEncoder

/**
 * Links people share (D-078). `pushly.app` is not ours (Q-01), so share links point to small pages on the GitHub
 * Pages site that open the app (`pushly://u/<name>`); the apps also parse these URLs (QR scanner, [DeepLink]).
 * Same as iOS `ShareLinks`.
 */
object ShareLinks {
    const val HOST = "danoujesky.github.io"
    const val SITE_FOLDER = "Pushly---PushUp-Wars"
    const val BASE = "https://$HOST/$SITE_FOLDER/"

    /** `https://danoujesky.github.io/Pushly---PushUp-Wars/u/?n=<username>` — add me as a friend. */
    fun profile(username: String): String = BASE + "u/?n=" + URLEncoder.encode(username, "UTF-8")

    /** The username in a scanned / pasted friend link (share page, pushly://u/…, pushly.app/u/…), or null. */
    fun username(text: String): String? = (DeepLink.parse(text.trim()) as? DeepLink.User)?.username
}
