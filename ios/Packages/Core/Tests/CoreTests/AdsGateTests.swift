import Foundation
import Testing
@testable import Core

private struct GateCase: Decodable {
    let id: String
    let placement: String
    let context: AdsGate.Context
    let allowed: Bool
    let reason: String
}

private struct GateFile: Decodable { let cases: [GateCase] }

struct AdsGateTests {
    @Test func sharedVectors() throws {
        let data = try Data(contentsOf: RepoFile.url("shared/test-vectors/ads/gate.json"))
        let file = try JSONDecoder().decode(GateFile.self, from: data)
        #expect(file.cases.count >= 20)
        for c in file.cases {
            let got = AdsGate.canShow(c.placement, c.context)
            #expect(got.allowed == c.allowed && got.reason == c.reason, "\(c.id): \(got)")
        }
    }
}
