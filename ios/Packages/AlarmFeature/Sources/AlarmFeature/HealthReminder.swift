import AlarmDomain
import Foundation
import UserNotifications

/// Evening local notification when the alarm can't ring (doc 04 §8). Only shown if notifications are allowed;
/// the in-app banner is the primary warning.
@MainActor
public final class HealthReminder {
    static let identifier = "app.pushly.health.evening"
    private var lastScheduled: Date?
    private var cleared = false

    public init() {}

    public func update(critical: Bool, nextAlarm: Date?, now: Date) {
        let center = UNUserNotificationCenter.current()
        guard let at = AlarmHealth.eveningReminder(critical: critical, nextAlarm: nextAlarm, now: now, zone: .current) else {
            if !cleared {
                center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
                cleared = true
                lastScheduled = nil
            }
            return
        }
        guard at != lastScheduled else { return }
        lastScheduled = at
        cleared = false
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Your alarm may not ring")
        content.body = String(localized: "Open Pushly and fix the warning before you go to sleep.")
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: at)
        let request = UNNotificationRequest(identifier: Self.identifier, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        center.add(request) { _ in }
    }
}
