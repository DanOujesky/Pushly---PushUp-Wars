import Core
import Foundation
import Testing
@testable import Networking

@Suite("Networking models — shared fixtures")
struct ModelTests {
    @Test func decodesProfileFixture() throws {
        let data = try Data(contentsOf: RepoFile.url("shared/contracts/fixtures/profile.json"))
        let profile = try JSONDecoder().decode(Profile.self, from: data)
        #expect(profile.username == "AnaFit")
        #expect(profile.onboardingCompleted)
        #expect(profile.country == "CZ")
        #expect(profile.birthYear == 2000)
        #expect(profile.profileVisibility == .public)
        #expect(profile.level == 7)
        #expect(!profile.isPro)
    }

    @Test func patchOmitsNilFields() throws {
        let json = try JSONEncoder().encode(ProfilePatch(username: "Dan", birthYear: 2000))
        let dict = try #require(JSONSerialization.jsonObject(with: json) as? [String: Any])
        #expect(Set(dict.keys) == ["username", "birth_year"])
        #expect(ProfilePatch().isEmpty)
    }

    @Test func remoteConfigFromFixture() throws {
        let data = try Data(contentsOf: RepoFile.url("shared/contracts/fixtures/app_config.json"))
        let rows = try JSONDecoder().decode([AppConfigRow].self, from: data)
        let config = RemoteConfig(rows: rows, platform: "ios")
        #expect(config.minSupportedVersion == "1.0.0")
        #expect(config.killSwitches["battles"] == false)
    }

    @Test func errorMapping() {
        #expect(BackendErrorMapper.map(postgresCode: "23505", message: "").code == .conflict)
        #expect(BackendErrorMapper.map(postgresCode: "22023", message: "minimum age is 16").code == .validationFailed)
        #expect(BackendErrorMapper.map(postgresCode: nil, message: "?").code == .unknown)
        #expect(BackendErrorMapper.map(URLError(.notConnectedToInternet)).retryable)
    }

    @Test func backendConfigRejectsUnexpandedBuildSettings() {
        // Info.plist values like "$(SUPABASE_URL)" mean the xcconfig had no value → offline mode
        let bundle = Bundle(for: BundleToken.self)
        #expect(BackendConfig.fromInfoPlist(bundle) == nil)
    }
}

private final class BundleToken {}

enum RepoFile {
    static func url(_ relative: String, file: StaticString = #filePath) -> URL {
        var root = URL(fileURLWithPath: "\(file)")
        for _ in 0..<6 { root.deleteLastPathComponent() }
        return root.appendingPathComponent(relative)
    }
}
