package app.pushly.core.designsystem

import androidx.compose.foundation.clickable
import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role

/**
 * Tap any player or clan → their page (D-080). Features don't know each other (doc 03 §3): the app provides
 * [LocalProfileLinks] and every list makes its rows [profileLink]. Pages open full screen on top of everything
 * (also over sheets) and stack: player → clan → player… Same as iOS `ProfileLink`.
 */
sealed interface ProfileTarget {
    data class User(val id: String) : ProfileTarget
    data class Username(val name: String) : ProfileTarget
    data class Clan(val id: String) : ProfileTarget
}

/** Opens a page; null when there is no account / backend (rows are then not clickable). */
val LocalProfileLinks = staticCompositionLocalOf<((ProfileTarget) -> Unit)?> { null }

/** Makes a row open [target]'s page. */
@Composable
fun Modifier.profileLink(target: ProfileTarget?): Modifier {
    val open = LocalProfileLinks.current
    return if (open != null && target != null) clickable(role = Role.Button) { open(target) } else this
}
