import Core
import Foundation
import Testing
@testable import WakeFlowFeature

@MainActor
@Suite("Rep-log outbox")
struct SessionUploaderTests {
    static func fixture() throws -> Data {
        var root = URL(fileURLWithPath: "\(#filePath)")
        for _ in 0..<6 { root.deleteLastPathComponent() }
        return try Data(contentsOf: root.appendingPathComponent("shared/contracts/fixtures/submit_rep_session_response.json"))
    }

    static func log(_ id: String) -> RepLog {
        RepTimeline(monotonicStartMs: 0, wallStart: Date(timeIntervalSince1970: 1_792_472_520))
            .log(sessionId: id, context: "training", occurrenceId: nil, outcome: "completed", snoozes: 0, rejected: [:],
                 anchor: nil, ringAtMonotonicMs: nil, appVersion: "0.1.0 (1)", deviceModel: "test", motionSuspicion: 0)
    }

    func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "uploader-\(UUID().uuidString)")
    }

    @Test func uploadsAndKeepsTheServerResult() async throws {
        let response = try Self.fixture()
        let dir = tempDir()
        let uploader = SessionUploader(directory: dir, sleep: { _ in }) { { _ in response } }
        uploader.enqueue(Self.log("f0000000-0000-4000-8000-000000000001"))
        await uploader.flush()
        #expect(uploader.pending.isEmpty)
        #expect(uploader.results["f0000000-0000-4000-8000-000000000001"]?.wake?.status == "succeeded")
        let progress = uploader.results["f0000000-0000-4000-8000-000000000001"]?.progress
        #expect(progress?.xpGained == 40)
        #expect(progress?.newAchievements.map(\.id) == ["first_wake", "textbook"])
        // Results survive a restart.
        let reopened = SessionUploader(directory: dir, sleep: { _ in }) { nil }
        #expect(reopened.results["f0000000-0000-4000-8000-000000000001"]?.streak.current == 1)
    }

    @Test func keepsTheQueueWhileSignedOutOrOffline() async {
        let dir = tempDir()
        let offline = SessionUploader(directory: dir, sleep: { _ in try? await Task.sleep(for: .seconds(3600)) }) {
            { _ in throw AppError(code: .network, message: "offline") }
        }
        offline.enqueue(Self.log("f0000000-0000-4000-8000-000000000002"))
        await offline.flush()
        #expect(offline.isPending(sessionId: "f0000000-0000-4000-8000-000000000002"))
        let signedOut = SessionUploader(directory: dir, sleep: { _ in }) { nil }
        await signedOut.flush()
        #expect(signedOut.pending.count == 1, "queue survives restarts")
    }

    @Test func dropsLogsTheServerRefusesForGood() async {
        let uploader = SessionUploader(directory: tempDir(), sleep: { _ in }) {
            { _ in throw AppError(code: .validationFailed, message: "invalid rep log") }
        }
        uploader.enqueue(Self.log("f0000000-0000-4000-8000-000000000003"))
        await uploader.flush()
        #expect(uploader.pending.isEmpty)
    }
}
