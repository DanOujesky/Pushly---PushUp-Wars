import Foundation
import Networking
@testable import ProfileFeature
import Testing

private actor FakeAccount: AccountServicing {
    var optOut = false
    var failWrites = false

    func setFailWrites(_ on: Bool) { failWrites = on }
    func exportMyData() async throws -> Data { Data("{}".utf8) }
    func deleteMyAccount() async throws {}
    func notificationPrefs() async throws -> Data { Data("{}".utf8) }
    func setNotificationPrefs(_ prefs: Data) async throws -> Data { prefs }
    func privacySettings() async throws -> Data { Data("{\"ghostOptOut\": \(optOut)}".utf8) }
    func registerPushToken(deviceId: String, token: String) async throws {}
    func setGhostOptOut(_ optOut: Bool) async throws {
        if failWrites { throw URLError(.notConnectedToInternet) }
        self.optOut = optOut
    }
}

@MainActor
struct AccountModelTests {
    @Test func ghostContributionLoadsAndSaves() async {
        let fake = FakeAccount()
        let model = AccountModel(account: fake) {}
        await model.load()
        #expect(model.ghostContribution)
        await model.setGhostContribution(false)
        #expect(!model.ghostContribution)
        #expect(await fake.optOut)
    }

    @Test func failedSaveRollsBack() async {
        let fake = FakeAccount()
        await fake.setFailWrites(true)
        let model = AccountModel(account: fake) {}
        await model.setGhostContribution(false)
        #expect(model.ghostContribution)
        #expect(model.message != nil)
    }
}
