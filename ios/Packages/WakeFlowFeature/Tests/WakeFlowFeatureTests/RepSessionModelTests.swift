import Compression
import Core
import Foundation
import RepEngine
import Testing
@testable import WakeFlowFeature

enum Vector {
    static func frames(_ name: String, file: StaticString = #filePath) throws -> [PoseFrame] {
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
}

@MainActor
@Suite("Rep session")
struct RepSessionModelTests {
    let size = CGSize(width: 1280, height: 720)

    @Test func wakeSessionFinishesAtTarget() throws {
        var summary: RepSessionModel.Summary?
        let model = RepSessionModel(mode: .wake(target: 5)) { summary = $0 }
        for f in try Vector.frames("synthetic-good-10-normal") { model.ingest(f, imageSize: size) }
        #expect(model.finished)
        #expect(model.counted == 5)
        #expect(model.remaining == 0)
        #expect(summary?.reps == 5)
        #expect((summary?.averageQuality ?? 0) > 0)
    }

    @Test func trainingCountsEverythingAndHintsBadForm() throws {
        let model = RepSessionModel(mode: .training) { _ in }
        for f in try Vector.frames("synthetic-mixed-session") { model.ingest(f, imageSize: size) }
        #expect(!model.finished)
        #expect(model.counted == 7)
        #expect(model.summary.rejected[.notDeepEnough] == 2)
    }

    @Test func cheatsCountNothing() throws {
        let model = RepSessionModel(mode: .wake(target: 3)) { _ in }
        for f in try Vector.frames("synthetic-cheat-arm-waving-lying") { model.ingest(f, imageSize: size) }
        #expect(model.counted == 0)
        #expect(!model.finished)
    }

    @Test func recorderExportReplaysToTheSameCount() throws {
        let model = RepSessionModel(mode: .training, record: true) { _ in }
        for f in try Vector.frames("synthetic-good-10-normal") { model.ingest(f, imageSize: size) }
        let recorder = try #require(model.recorder)
        let url = try recorder.export(label: .init(humanCount: 10, tags: ["normal"]), device: "test")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(url.lastPathComponent.hasPrefix("real-side-10-"))
        struct File: Decodable {
            struct Frame: Decodable { let t: Int64; let lm: [[Double]]; let w: [[Double]] }
            struct Expected: Decodable { let counted: Int }
            let frames: [Frame]
            let expected: Expected
        }
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        #expect(file.expected.counted == 10)
        let engine = RepEngine(imageWidth: 1280, imageHeight: 720)
        for f in file.frames {
            _ = engine.process(PoseFrame(
                tMs: f.t,
                landmarks: f.lm.map { PoseLandmark(x: $0[0], y: $0[1], z: $0[2], visibility: $0[3], presence: $0[4]) },
                world: f.w.map { WorldPoint(x: $0[0], y: $0[1], z: $0[2]) }
            ))
        }
        #expect(engine.counted == 10)
    }

    @Test func repLogFollowsTheContract() throws {
        let clock = FixedClock(now: Date(timeIntervalSince1970: 1_792_472_520), monotonicMs: 500_000)
        let model = RepSessionModel(mode: .training, clock: clock) { _ in }
        var last: Int64?
        for f in try Vector.frames("synthetic-good-10-normal") {
            if let last { clock.advance(byMs: f.tMs - last) }
            last = f.tMs
            model.ingest(f, imageSize: size)
        }
        model.finish()
        let log = model.repLog(sessionId: "f0000000-0000-4000-8000-000000000001", context: "training", appVersion: "0.1.0 (1)")
        #expect(log.reps.count == 10)
        #expect(log.reps.map(\.i) == Array(1...10))
        for (k, r) in log.reps.enumerated() {
            #expect(r.tStartMs <= r.tBottomMs && r.tBottomMs <= r.tEndMs)
            #expect(r.tEndMs - r.tStartMs >= 450, "rep \(k + 1) duration")
            if k > 0 { #expect(r.tStartMs >= log.reps[k - 1].tEndMs) }
        }
        #expect(log.timing.monotonicStartMs == 500_000)
        #expect(log.featureTrace != nil, "the 10 Hz feature trace goes with every log")
        #expect(log.suspicion.continuity == 0 && log.suspicion.replay == 0)
        #expect(log.timing.monotonicEndMs - log.timing.monotonicStartMs >= log.reps[9].tEndMs)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(log)) as? [String: Any]
        #expect(json?["platform"] as? String == "ios")
        #expect((json?["context"] as? [String: Any])?["type"] as? String == "training")
    }

    @Test func decodesTheSharedRepLogVector() throws {
        // The same contract fixtures the server tests use (shared/test-vectors/rep-log).
        var root = URL(fileURLWithPath: "\(#filePath)")
        for _ in 0..<6 { root.deleteLastPathComponent() }
        struct File: Decodable { struct Case: Decodable { let id: String; let log: RepLog }; let cases: [Case] }
        let data = try Data(contentsOf: root.appendingPathComponent("shared/test-vectors/rep-log/cases.json"))
        let file = try JSONDecoder().decode(File.self, from: data)
        #expect(file.cases.count >= 15)
    }

    @Test func setsAndSprintMarkers() {
        var tl = RepTimeline(monotonicStartMs: 1000, wallStart: Date(timeIntervalSince1970: 0))
        tl.startSprint(monotonicNow: 4000)
        tl.startSprint(monotonicNow: 9000)
        tl.appendSet(startMs: 100, endMs: 50)
        tl.end(monotonicNow: 20_000)
        #expect(tl.sprintStartMs == 3000)
        #expect(tl.sets == [RepLog.SetSpan(startMs: 100, endMs: 100)])
        #expect(tl.monotonicEndMs == 20_000)
    }
}
