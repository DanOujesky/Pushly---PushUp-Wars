import Foundation

/// Report anything another user did (doc 06 §6, doc 16 §5, App Store guideline 1.2): features call
/// `Reporter.send(.user(id), reason)`; the app installs the backend call (`report(target, reason)`).
public enum ReportTarget: Sendable, Hashable {
    case user(String)
    case battle(String)
    case message(Int)
    case clan(String)

    /// `target` argument of the `report` RPC.
    public var json: [String: String] {
        switch self {
        case let .user(id): ["userId": id]
        case let .battle(id): ["battleId": id]
        case let .message(id): ["messageId": String(id)]
        case let .clan(id): ["clanId": id]
        }
    }
}

public enum Reporter {
    /// Returns true when the report was stored. Without a handler (guest / no backend) reporting is unavailable.
    @MainActor public static var handler: ((ReportTarget, String) async -> Bool)?

    @MainActor public static var isAvailable: Bool { handler != nil }

    @MainActor public static func send(_ target: ReportTarget, reason: String) async -> Bool {
        await handler?(target, reason) ?? false
    }
}
