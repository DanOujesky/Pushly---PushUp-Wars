import Foundation

/// Asks for notification permission in context (doc 02 PS-06): features call `PushPrompt.request(.friends)` after an
/// action that benefits from notifications (friend request, clan join, battle challenge). The app installs the
/// handler (explainer first, then the system prompt, once); without a handler this does nothing.
public enum PushPrompt {
    public enum Reason: String, Sendable {
        case friends, clan, battles
    }

    @MainActor public static var handler: (Reason) -> Void = { _ in }

    @MainActor public static func request(_ reason: Reason) { handler(reason) }
}
