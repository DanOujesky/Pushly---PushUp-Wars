import Core
import Foundation
import Observation

/// The five main tabs (doc 02 §1).
enum AppTab: String, CaseIterable, Hashable, Sendable {
    case wake, battle, clan, training, profile
}

/// App-wide navigation state. Features never navigate to each other directly (doc 03 §3);
/// they ask the router.
@MainActor
@Observable
final class AppRouter {
    /// Battle is the home screen (D-076); an alarm or a link still switches to its tab.
    var selectedTab: AppTab = .battle
    /// The last deep link that still needs a feature screen to consume it (feature screens arrive in later phases).
    private(set) var pendingLink: DeepLink?

    func handle(url: URL) {
        guard let link = DeepLink(url: url) else {
            PLog.warning("Ignored unknown deep link", .app)
            return
        }
        open(link)
    }

    /// A player profile opened from a link (pushly://u/{username}); shown as a sheet over the current tab.
    var profileUsername: String?

    func open(_ link: DeepLink) {
        if case let .user(username) = link {
            profileUsername = username
            return
        }
        selectedTab = Self.tab(for: link)
        pendingLink = link
    }

    func consumePendingLink() -> DeepLink? {
        defer { pendingLink = nil }
        return pendingLink
    }

    static func tab(for link: DeepLink) -> AppTab {
        switch link {
        case .wake, .alarm, .alarmHealth: .wake
        case .battle, .battleInvite, .leaderboard: .battle
        case .clan, .clanWar: .clan
        case .user, .pro: .profile
        }
    }
}
