import Compression
import Foundation
import Testing
@testable import RepEngine

enum RepoFile {
    static func url(_ relative: String, file: StaticString = #filePath) -> URL {
        // .../ios/Packages/RepEngine/Tests/RepEngineTests/<file>.swift → repo root is 6 levels up
        var root = URL(fileURLWithPath: "\(file)")
        for _ in 0..<6 { root.deleteLastPathComponent() }
        return root.appendingPathComponent(relative)
    }
}

/// Minimal gunzip for the vector files (python gzip, no optional header fields).
enum Gzip {
    static func decompress(_ data: Data) -> Data? {
        guard data.count > 18, data[0] == 0x1f, data[1] == 0x8b, data[3] == 0 else { return nil }
        let size = data.suffix(4).enumerated().reduce(0) { $0 | (Int($1.element) << (8 * $1.offset)) }
        let body = data.subdata(in: 10..<(data.count - 8))
        var out = Data(count: size)
        let written = out.withUnsafeMutableBytes { dst in
            body.withUnsafeBytes { src in
                compression_decode_buffer(
                    dst.bindMemory(to: UInt8.self).baseAddress!, size,
                    src.bindMemory(to: UInt8.self).baseAddress!, body.count, nil, COMPRESSION_ZLIB)
            }
        }
        return written == size ? out : nil
    }
}

private struct VectorFile: Decodable {
    struct Meta: Decodable { let imageWidth: Double; let imageHeight: Double; let tags: [String] }
    struct Frame: Decodable { let t: Int64; let lm: [[Double]]; let w: [[Double]]; let motion: Double? }
    struct Event: Decodable, Equatable {
        let type: String
        let t: Int64
        let reason: String?
        let index: Int?
        let quality: Int?
    }
    struct Result: Decodable { let counted: Int; let rejected: [String: Int]; let events: [Event] }
    struct Expected: Decodable { let counted: Int; let rejected: [String: Int]? }
    let id: String
    let meta: Meta
    let frames: [Frame]
    let expected: Expected
    let reference: Result
}

/// Runs every shared push-up vector (Android RepVectorsTest runs the same files — CLAUDE.md §4.1). The engine must
/// match the human label and reproduce the reference engine's events exactly (quality ±1).
@Suite("Push-up vectors")
struct RepVectorTests {
    @Test func allVectorsMatchLabelsAndReference() throws {
        let dir = RepoFile.url("shared/test-vectors/pushup")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix(".json.gz") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        #expect(files.count >= 25)
        for file in files {
            let raw = try #require(Gzip.decompress(try Data(contentsOf: file)), "gunzip \(file.lastPathComponent)")
            let v = try JSONDecoder().decode(VectorFile.self, from: raw)
            let engine = RepEngine(imageWidth: v.meta.imageWidth, imageHeight: v.meta.imageHeight)
            var events: [RepEvent] = []
            for f in v.frames {
                let frame = PoseFrame(
                    tMs: f.t,
                    landmarks: f.lm.map { PoseLandmark(x: $0[0], y: $0[1], z: $0[2], visibility: $0[3], presence: $0[4]) },
                    world: f.w.map { WorldPoint(x: $0[0], y: $0[1], z: $0[2]) },
                    motion: f.motion
                )
                events += engine.process(frame)
            }
            var rejected: [String: Int] = [:]
            for case let .rejected(reason, _) in events { rejected[reason.rawValue, default: 0] += 1 }
            #expect(engine.counted == v.expected.counted, "\(v.id): counted")
            if let expectedRejected = v.expected.rejected { #expect(rejected == expectedRejected, "\(v.id): rejected") }
            if v.meta.tags.contains("cheat") { #expect(engine.counted == 0, "\(v.id): cheat must count 0") }

            // Parity with the reference engine, event by event.
            #expect(events.count == v.reference.events.count, "\(v.id): event count")
            for (mine, ref) in zip(events, v.reference.events) {
                switch mine {
                case let .counted(r):
                    #expect(ref.type == "counted" && ref.index == r.index && ref.t == r.tEnd, "\(v.id): counted rep \(r.index)")
                    #expect(abs((ref.quality ?? -99) - r.quality) <= 1, "\(v.id): quality \(r.quality) vs \(ref.quality ?? -1)")
                case let .rejected(reason, t):
                    #expect(ref.type == "rejected" && ref.reason == reason.rawValue && ref.t == t, "\(v.id): rejection \(reason)")
                }
            }
        }
    }

    @Test func reversalsIgnoreSmallWiggles() {
        #expect(RepMath.reversals([150, 120, 90, 95, 120, 160], threshold: 8) == 1)
        #expect(RepMath.reversals([150, 120, 125, 100, 160], threshold: 8) == 1)
        #expect(RepMath.reversals([150, 110, 135, 85, 160], threshold: 8) == 3)
    }

    @Test func angleBasics() {
        #expect(abs(RepMath.angle([1, 0], [0, 0], [0, 1]) - 90) < 1e-9)
        #expect(RepMath.angle([0, 0], [0, 0], [1, 1]) == 180)
    }
}
