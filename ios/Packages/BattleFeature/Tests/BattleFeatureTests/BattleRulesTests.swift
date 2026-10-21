import Foundation
import Testing
@testable import BattleFeature

enum RepoFile {
    static func data(_ relative: String, file: StaticString = #filePath) throws -> Data {
        // .../ios/Packages/BattleFeature/Tests/BattleFeatureTests/<file>.swift → repo root is 6 levels up
        var root = URL(fileURLWithPath: "\(file)")
        for _ in 0..<6 { root.deleteLastPathComponent() }
        return try Data(contentsOf: root.appendingPathComponent(relative))
    }
}

private struct VectorCase: Decodable {
    let id: String
    let mode: String
    let variant: [String: Int]
    let a: [BattleRules.Rep]
    let b: [BattleRules.Rep]
    let expected: BattleRules.Result
}

private struct VectorFile: Decodable { let cases: [VectorCase] }

struct BattleRulesTests {
    @Test func sharedVectors() throws {
        let file = try JSONDecoder().decode(VectorFile.self, from: RepoFile.data("shared/test-vectors/battles/results.json"))
        #expect(file.cases.count >= 20)
        for c in file.cases {
            let got = BattleRules.decide(mode: c.mode, variant: c.variant, a: c.a, b: c.b)
            #expect(got == c.expected, "\(c.id): \(got)")
        }
    }
}
