import Compression
import Foundation
import RepEngine
import Testing
@testable import WakeFlowFeature

private enum Vector {
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
}
