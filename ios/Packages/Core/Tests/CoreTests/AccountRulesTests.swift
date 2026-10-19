import Foundation
import Testing
@testable import Core

/// Runs the shared account vectors (shared/test-vectors/account/rules.json) — Android runs the same file.
@Suite("Account rules — shared vectors")
struct AccountRulesTests {
    struct Vectors: Decodable {
        struct Username: Decodable { let name: String; let error: String? }
        struct BirthYear: Decodable { let birthYear: Int; let currentYear: Int; let error: String? }
        struct Version: Decodable { let app: String; let minSupported: String; let updateRequired: Bool }
        let usernames: [Username]
        let birthYears: [BirthYear]
        let versions: [Version]
    }

    static func load() throws -> Vectors {
        let data = try Data(contentsOf: RepoFile.url("shared/test-vectors/account/rules.json"))
        return try JSONDecoder().decode(Vectors.self, from: data)
    }

    @Test func usernames() throws {
        for v in try Self.load().usernames {
            #expect(AccountRules.usernameError(v.name)?.rawValue == v.error, "username \(v.name)")
        }
    }

    @Test func birthYears() throws {
        for v in try Self.load().birthYears {
            #expect(AccountRules.birthYearError(v.birthYear, currentYear: v.currentYear)?.rawValue == v.error,
                    "birth year \(v.birthYear)")
        }
    }

    @Test func versions() throws {
        for v in try Self.load().versions {
            #expect(AppVersion.updateRequired(app: v.app, minSupported: v.minSupported) == v.updateRequired,
                    "\(v.app) vs \(v.minSupported)")
        }
    }

    @Test func birthYearPickerStartsAtMinimumAge() {
        let years = AccountRules.selectableBirthYears(currentYear: 2026)
        #expect(years.first == 2010)
        #expect(years.allSatisfy { AccountRules.birthYearError($0, currentYear: 2026) == nil })
    }
}

/// Locates files in the repository from test sources (works locally and in CI because sources are checked out).
enum RepoFile {
    static func url(_ relative: String, file: StaticString = #filePath) -> URL {
        // .../ios/Packages/Core/Tests/CoreTests/<file>.swift → repo root is 6 levels up
        var root = URL(fileURLWithPath: "\(file)")
        for _ in 0..<6 { root.deleteLastPathComponent() }
        return root.appendingPathComponent(relative)
    }
}
