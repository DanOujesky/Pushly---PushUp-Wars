import AlarmDomain
import Compression
import Core
import Foundation
import RepEngine
import Testing
@testable import AlarmFeature
@testable import WakeFlowFeature

private func frames(_ name: String, file: StaticString = #filePath) throws -> [PoseFrame] {
    var root = URL(fileURLWithPath: "\(file)")
    for _ in 0..<6 { root.deleteLastPathComponent() }
    let data = try Data(contentsOf: root.appendingPathComponent("shared/test-vectors/pushup/\(name).json.gz"))
    let size = data.suffix(4).enumerated().reduce(0) { $0 | (Int($1.element) << (8 * $1.offset)) }
    let body = data.subdata(in: 10..<(data.count - 8))
    var out = Data(count: size)
    _ = out.withUnsafeMutableBytes { dst in
        body.withUnsafeBytes { src in
            compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, size,
                                      src.bindMemory(to: UInt8.self).baseAddress!, body.count, nil, COMPRESSION_ZLIB)
        }
    }
    struct File: Decodable {
        struct Frame: Decodable { let t: Int64; let lm: [[Double]]; let w: [[Double]] }
        let frames: [Frame]
    }
    return try JSONDecoder().decode(File.self, from: out).frames.map { f in
        PoseFrame(tMs: f.t,
                  landmarks: f.lm.map { PoseLandmark(x: $0[0], y: $0[1], z: $0[2], visibility: $0[3], presence: $0[4]) },
                  world: f.w.map { WorldPoint(x: $0[0], y: $0[1], z: $0[2]) })
    }
}

/// Same cases as Android WakeChallengeTest.
@MainActor
@Suite("Wake challenge")
struct WakeChallengeModelTests {
    let t0 = Date(timeIntervalSince1970: 1_792_472_400) // 2026-10-20T05:00:00Z
    let size = CGSize(width: 1280, height: 720)

    func ring(_ mode: ChallengeMode) -> RingState {
        RingState(occurrenceId: "a0000000-0000-4000-8000-000000000001:2026-10-20",
                  alarmId: "a0000000-0000-4000-8000-000000000001", label: "Up", t0: ISOInstant.format(t0),
                  rangAt: ISOInstant.format(t0), mode: mode, countsForChallenge: true)
    }

    func run(_ challenge: WakeChallengeModel, _ clock: FixedClock, _ name: String) throws {
        var last: Int64?
        for f in try frames(name) {
            if let last { clock.advance(byMs: f.tMs - last) }
            last = f.tMs
            challenge.reps.ingest(f, imageSize: size)
            challenge.tick()
        }
    }

    @Test func ringUntilDoneSucceedsAtTarget() throws {
        let clock = FixedClock(now: t0.addingTimeInterval(60))
        var over: Bool?
        let challenge = WakeChallengeModel(ring: ring(ChallengeMode(type: "ringUntilDone", targetReps: 5)), services: nil,
                                           clock: clock)
        challenge.onOver = { over = $0 }
        try run(challenge, clock, "synthetic-good-10-normal")
        #expect(over == true)
        #expect(challenge.decision?.status == "succeeded")
        #expect(challenge.phase == .done)
    }

    @Test func cheatingNeverFinishesAndGivingUpFails() throws {
        let clock = FixedClock(now: t0.addingTimeInterval(60))
        let challenge = WakeChallengeModel(ring: ring(ChallengeMode(type: "ringUntilDone", targetReps: 5)), services: nil,
                                           clock: clock)
        try run(challenge, clock, "synthetic-cheat-arm-waving-lying")
        #expect(challenge.decision == nil)
        challenge.giveUp()
        #expect(challenge.decision?.status == "failed")
    }

    @Test func setsSplitsTheRepsAndStartsARest() throws {
        let clock = FixedClock(now: t0.addingTimeInterval(60))
        let challenge = WakeChallengeModel(
            ring: ring(ChallengeMode(type: "sets", sets: 2, repsPerSet: 4, restSeconds: 600)), services: nil, clock: clock)
        try run(challenge, clock, "synthetic-good-10-normal")
        #expect(challenge.decision?.status == "succeeded")
        let sets = try #require(challenge.reps.timeline).sets
        #expect(sets.count == 2)
        #expect(sets[1].startMs > sets[0].endMs)
    }

    @Test func deadlineExpiresTheChallenge() {
        let clock = FixedClock(now: t0.addingTimeInterval(31 * 60))
        let challenge = WakeChallengeModel(ring: ring(ChallengeMode(type: "ringUntilDone", targetReps: 20)), services: nil,
                                           clock: clock)
        challenge.tick()
        #expect(challenge.decision?.status == "failed")
        #expect(challenge.reps.outcome == "expired")
    }
}
