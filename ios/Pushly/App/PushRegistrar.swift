import Core
import Networking
import Observation
import UIKit
import UserNotifications
import WakeFlowFeature

/// Remote notifications (doc 15 §2, P6-06): in-context explainer → system prompt → APNs token → `register_push_token`
/// for this install's device row. Never asks at launch or during the wake flow; alarms never depend on it.
@MainActor
@Observable
final class PushRegistrar {
    static let shared = PushRegistrar()

    /// Shown before the system prompt (pre-permission explainer, CLAUDE.md §10).
    var explainer: PushPrompt.Reason?

    private let defaults = UserDefaults.standard
    private let askedKey = "push.explainerShown"
    private weak var session: AppSession?
    private var lastToken: String?

    func attach(_ session: AppSession) {
        self.session = session
        PushPrompt.handler = { [weak self] reason in self?.prompt(reason) }
    }

    /// After sign-in / at launch: re-register when the user already allowed notifications (tokens can change).
    func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard [.authorized, .provisional].contains(settings.authorizationStatus) else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    private func prompt(_ reason: PushPrompt.Reason) {
        guard !defaults.bool(forKey: askedKey) else { return }
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                explainer = reason
            } else {
                await refresh()
            }
        }
    }

    func explainerAnswered(allow: Bool) {
        explainer = nil
        defaults.set(true, forKey: askedKey)
        guard allow else { return }
        Task {
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            if granted { UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    func didRegister(token: Data) {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        guard hex != lastToken, let backend = session?.repSessions, let account = session?.account else { return }
        Task {
            do {
                // The device row comes from the same idempotent registration the rep-log signer uses (D-047).
                let signer = LogSigner(key: DeviceKey.loadOrCreate(), appVersion: session?.appVersion ?? "0") { request in
                    try await backend.registerDevice(request)
                }
                let deviceId = try await signer.deviceId()
                try await account.registerPushToken(deviceId: deviceId, token: hex)
                lastToken = hex
                PLog.info("Push token registered", .sync)
            } catch {
                PLog.warning("Push token not registered: \(error)", .sync)
            }
        }
    }
}

/// UIKit callbacks for remote notification registration.
final class PushAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        MainActor.assumeIsolated { PushRegistrar.shared.didRegister(token: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PLog.warning("APNs registration failed: \(error)", .sync)
    }
}
