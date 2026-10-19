import Foundation

/// Deep links (doc 15 §3). Accepts `pushly://<path>` and `https://pushly.app/<path>`.
public enum DeepLink: Equatable, Sendable {
    case wake
    case alarm(id: UUID)
    case battleInvite(code: String)
    case battle(id: UUID)
    case clan(id: UUID)
    case clanWar(id: UUID)
    case user(username: String)
    case leaderboard(board: String)
    case alarmHealth
    case pro

    public static let webHost = "pushly.app"
    public static let scheme = "pushly"

    public init?(url: URL) {
        let parts: [String]
        if url.scheme == Self.scheme {
            // pushly://battle/invite/AB12 → host = "battle", path = "/invite/AB12"
            parts = ([url.host ?? ""] + url.pathComponents.filter { $0 != "/" }).filter { !$0.isEmpty }
        } else if url.scheme == "https", url.host == Self.webHost {
            parts = url.pathComponents.filter { $0 != "/" }
        } else {
            return nil
        }
        guard let link = Self.parse(parts) else { return nil }
        self = link
    }

    private static func parse(_ p: [String]) -> DeepLink? {
        switch p.count {
        case 1:
            switch p[0] {
            case "wake": return .wake
            case "pro": return .pro
            default: return nil
            }
        case 2:
            switch p[0] {
            case "alarm": return UUID(uuidString: p[1]).map { .alarm(id: $0) }
            case "battle": return UUID(uuidString: p[1]).map { .battle(id: $0) }
            case "b": return validCode(p[1]).map { .battleInvite(code: $0) }  // short share link /b/{code}
            case "clan": return UUID(uuidString: p[1]).map { .clan(id: $0) }
            case "u": return validUsername(p[1]).map { .user(username: $0) }
            case "leaderboard": return validBoard(p[1]).map { .leaderboard(board: $0) }
            case "settings" where p[1] == "alarm-health": return .alarmHealth
            default: return nil
            }
        case 3:
            if p[0] == "battle", p[1] == "invite" { return validCode(p[2]).map { .battleInvite(code: $0) } }
            if p[0] == "clan", p[1] == "war" { return UUID(uuidString: p[2]).map { .clanWar(id: $0) } }
            return nil
        default:
            return nil
        }
    }

    private static func validCode(_ s: String) -> String? {
        s.range(of: "^[A-Za-z0-9]{4,12}$", options: .regularExpression) != nil ? s : nil
    }

    private static func validUsername(_ s: String) -> String? {
        s.range(of: "^[A-Za-z0-9_.]{3,20}$", options: .regularExpression) != nil ? s : nil
    }

    private static func validBoard(_ s: String) -> String? {
        ["wake", "streak", "battles", "total", "clans"].contains(s) ? s : nil
    }
}
