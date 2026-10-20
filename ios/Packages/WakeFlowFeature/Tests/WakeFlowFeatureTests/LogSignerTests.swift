import CryptoKit
import Foundation
import Testing
@testable import WakeFlowFeature

@Suite("Signed rep logs")
struct LogSignerTests {
    actor Calls {
        var registrations: [Data] = []
        func add(_ d: Data) { registrations.append(d) }
    }

    @Test func envelopeSignsTheExactLogBytes() async throws {
        let key = P256.Signing.PrivateKey()
        let calls = Calls()
        let signer = LogSigner(key: .software(key), appVersion: "0.1.0 (1)") { request in
            await calls.add(request)
            return "d0000000-0000-4000-8000-000000000001"
        }
        let log = Data(#"{"sessionId":"f0000000-0000-4000-8000-000000000001","reps":[]}"#.utf8)
        let body = try #require(try JSONSerialization.jsonObject(with: await signer.envelope(log)) as? [String: String])
        #expect(body["deviceId"] == "d0000000-0000-4000-8000-000000000001")
        #expect(body["log"].map { Data($0.utf8) } == log)
        let sig = try P256.Signing.ECDSASignature(rawRepresentation: try #require(Data(base64Encoded: try #require(body["signature"]))))
        #expect(key.publicKey.isValidSignature(sig, for: log))
        _ = await signer.envelope(log)
        let registrations = await calls.registrations
        #expect(registrations.count == 1, "the key is registered once per launch")
        let reg = try #require(try JSONSerialization.jsonObject(with: registrations[0]) as? [String: String])
        #expect(reg["platform"] == "ios")
        #expect(reg["publicKey"] == key.publicKey.derRepresentation.base64EncodedString())
    }

    @Test func registrationFailureFallsBackToTheBareLog() async {
        struct Offline: Error {}
        let signer = LogSigner(key: .software(), appVersion: "0.1.0 (1)") { _ in throw Offline() }
        let log = Data(#"{"reps":[]}"#.utf8)
        #expect(await signer.envelope(log) == log)
    }
}
