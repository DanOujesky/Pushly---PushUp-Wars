import Core
import Foundation
import Testing
@testable import Pushly

@MainActor
@Suite("AppRouter")
struct AppRouterTests {
    @Test func deepLinksSelectTheRightTab() {
        let router = AppRouter()
        router.handle(url: URL(string: "pushly://battle/invite/AB12")!)
        #expect(router.selectedTab == .battle)
        #expect(router.consumePendingLink() == .battleInvite(code: "AB12"))
        #expect(router.consumePendingLink() == nil)

        router.handle(url: URL(string: "https://pushly.app/u/AnaFit")!)
        #expect(router.selectedTab == .profile)
    }

    @Test func unknownLinksAreIgnored() {
        let router = AppRouter()
        router.selectedTab = .clan
        router.handle(url: URL(string: "pushly://nonsense")!)
        #expect(router.selectedTab == .clan)
        #expect(router.consumePendingLink() == nil)
    }
}
