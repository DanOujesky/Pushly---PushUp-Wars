import Foundation
import Testing
@testable import Core

@Suite("DeepLink parsing (doc 15 §3)")
struct DeepLinkTests {
    let id = UUID(uuidString: "a0000000-0000-4000-8000-000000000001")!

    @Test func customSchemeLinks() {
        #expect(DeepLink(url: URL(string: "pushly://wake")!) == .wake)
        #expect(DeepLink(url: URL(string: "pushly://pro")!) == .pro)
        #expect(DeepLink(url: URL(string: "pushly://alarm/\(id.uuidString)")!) == .alarm(id: id))
        #expect(DeepLink(url: URL(string: "pushly://battle/invite/AB12CD")!) == .battleInvite(code: "AB12CD"))
        #expect(DeepLink(url: URL(string: "pushly://clan/war/\(id.uuidString)")!) == .clanWar(id: id))
        #expect(DeepLink(url: URL(string: "pushly://settings/alarm-health")!) == .alarmHealth)
        #expect(DeepLink(url: URL(string: "pushly://leaderboard/wake")!) == .leaderboard(board: "wake"))
    }

    @Test func universalLinks() {
        #expect(DeepLink(url: URL(string: "https://pushly.app/u/AnaFit")!) == .user(username: "AnaFit"))
        #expect(DeepLink(url: URL(string: "https://pushly.app/b/XY99")!) == .battleInvite(code: "XY99"))
        #expect(DeepLink(url: URL(string: "https://pushly.app/battle/\(id.uuidString)")!) == .battle(id: id))
    }

    @Test func rejectsUnknownOrMalformed() {
        #expect(DeepLink(url: URL(string: "https://evil.example/u/AnaFit")!) == nil)
        #expect(DeepLink(url: URL(string: "pushly://alarm/not-a-uuid")!) == nil)
        #expect(DeepLink(url: URL(string: "pushly://u/a")!) == nil)
        #expect(DeepLink(url: URL(string: "pushly://leaderboard/secret")!) == nil)
        #expect(DeepLink(url: URL(string: "pushly://battle/invite/../../x")!) == nil)
        #expect(DeepLink(url: URL(string: "http://pushly.app/wake")!) == nil)
    }
}

@Suite struct LegalLinksTests {
    @Test func linksArePublicHttpsPages() {
        for url in [LegalLinks.privacy, LegalLinks.terms, LegalLinks.community, LegalLinks.deleteAccount, LegalLinks.support] {
            #expect(url.scheme == "https")
            #expect(url.absoluteString.hasPrefix(LegalLinks.base))
            #expect(url.pathExtension == "html")
        }
    }

    @Test func shareLinksRoundTrip() throws {
        let url = try #require(ShareLinks.profile("AnaFit"))
        #expect(url.absoluteString == "https://danoujesky.github.io/Pushly---PushUp-Wars/u/?n=AnaFit")
        #expect(DeepLink(url: url) == .user(username: "AnaFit"))
        #expect(ShareLinks.username(in: url.absoluteString) == "AnaFit")
        #expect(ShareLinks.username(in: "pushly://u/ondra_pushes") == "ondra_pushes")
        #expect(ShareLinks.username(in: "https://danoujesky.github.io/Pushly---PushUp-Wars/privacy.html") == nil)
        #expect(ShareLinks.username(in: "https://example.com/u/?n=AnaFit") == nil)
    }
}
