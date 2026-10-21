package app.pushly.core.common

/**
 * Asks for notification permission in context (doc 02 PS-06): features call `PushPrompt.request(Reason.Friends)` after
 * an action that benefits from notifications (friend request, clan join, battle challenge). The app installs the
 * handler (explainer first, then the system prompt, once); without a handler this does nothing. Same as iOS.
 */
object PushPrompt {
    enum class Reason { Friends, Clan, Battles }

    @Volatile var handler: (Reason) -> Unit = {}

    fun request(reason: Reason) = handler(reason)
}
