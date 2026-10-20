import Compression
import Foundation
import Testing
@testable import RepEngine

/// Shared integrity vectors (doc 06 §2.3–2.4) — Android SessionMonitorTest runs the same cases.
@Suite("Session integrity vectors")
struct SessionMonitorTests {
    struct Frame: Decodable { var t: Int64; var lm: [[Double]]; var w: [[Double]]; let motion: Double? }
    struct Pushup: Decodable {
        struct Meta: Decodable { let imageWidth: Double; let imageHeight: Double }
        let meta: Meta
        let frames: [Frame]
    }
    struct Transform: Decodable {
        let dropEveryMs: Int64?
        let gapMs: Int64?
        let freezeAt: Int?
        let freezeFrames: Int?
        let wobble: Double?
    }
    struct Expected: Decodable { let rows: [[Int64]]; let continuity: Double; let replay: Double; let gaps: Int; let frozen: Int }
    struct Case: Decodable { let id: String; let source: String; let transform: Transform; let expected: Expected }
    struct File: Decodable { let cases: [Case] }

    /// Same transforms as tools/reference/build_vectors.py `integrity_transform`.
    static func apply(_ tr: Transform, to input: [Frame]) -> [Frame] {
        var out = input
        if let every = tr.dropEveryMs, let gap = tr.gapMs, let t0 = out.first?.t {
            out = out.filter { ($0.t - t0) % every >= gap || $0.t == t0 }
        }
        if let k = tr.freezeAt, let n = tr.freezeFrames {
            for i in (k + 1)..<(k + n) {
                out[i].lm = out[k].lm
                out[i].w = out[k].w
            }
        }
        if let wobble = tr.wobble {
            for i in out.indices {
                let s = 1 + wobble * sin(Double(i) / 7.0)
                for j in [13, 14, 15, 16] { out[i].w[j] = out[i].w[j].map { $0 * s } }
            }
        }
        return out
    }

    @Test func casesMatchTheReference() throws {
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: RepoFile.url("shared/test-vectors/integrity/cases.json")))
        #expect(file.cases.count >= 5)
        for c in file.cases {
            let raw = try #require(Gzip.decompress(try Data(contentsOf: RepoFile.url("shared/test-vectors/pushup/\(c.source).json.gz"))))
            let v = try JSONDecoder().decode(Pushup.self, from: raw)
            let frames = Self.apply(c.transform, to: v.frames)
            let engine = RepEngine(imageWidth: v.meta.imageWidth, imageHeight: v.meta.imageHeight)
            var monitor = SessionMonitor()
            let t0 = frames[0].t
            for f in frames {
                let frame = PoseFrame(
                    tMs: f.t,
                    landmarks: f.lm.map { PoseLandmark(x: $0[0], y: $0[1], z: $0[2], visibility: $0[3], presence: $0[4]) },
                    world: f.w.map { WorldPoint(x: $0[0], y: $0[1], z: $0[2]) }, motion: f.motion)
                _ = engine.process(frame)
                monitor.frame(frame, features: engine.lastFeatures, relativeMs: f.t - t0)
            }
            #expect(monitor.gaps == c.expected.gaps, "\(c.id) gaps")
            #expect(monitor.frozen == c.expected.frozen, "\(c.id) frozen")
            #expect(abs(monitor.continuity - c.expected.continuity) <= 0.002, "\(c.id) continuity")
            #expect(abs(monitor.replay - c.expected.replay) <= 0.002, "\(c.id) replay")
            #expect(monitor.rows.count == c.expected.rows.count, "\(c.id) trace rows")
            for (mine, ref) in zip(monitor.rows, c.expected.rows) {
                #expect(mine[0] == ref[0] && zip(mine, ref).allSatisfy { abs($0 - $1) <= 1 }, "\(c.id) row \(ref[0])")
            }
        }
    }

    @Test func traceRoundTrips() throws {
        var monitor = SessionMonitor()
        let lm = (0..<33).map { _ in PoseLandmark(x: 0.5, y: 0.5, z: 0, visibility: 0.9, presence: 0.9) }
        let world = (0..<33).map { i in WorldPoint(x: Double(i) * 0.01, y: 0, z: 0) }
        let f = RepFeatures(t: 0, leftSide: true, visibility: 0.9, elbow: 91.4, bodyLine: 171.6, knee: 175, hipDeviation: 0,
                            torsoTilt: 5, bbox: 0.6, shoulderY: 100, upperArm: 50, placement: .side, motion: nil)
        monitor.frame(PoseFrame(tMs: 1000, landmarks: lm, world: world), features: f, relativeMs: 0)
        let encoded = try #require(monitor.encodedTrace)
        let packed = try #require(Data(base64Encoded: encoded))
        var out = Data(count: 4096)
        let n = out.withUnsafeMutableBytes { dst in
            packed.withUnsafeBytes { src in
                compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, 4096,
                                          src.bindMemory(to: UInt8.self).baseAddress!, packed.count, nil, COMPRESSION_ZLIB)
            }
        }
        let json = try #require(try JSONSerialization.jsonObject(with: out.prefix(n)) as? [String: Any])
        #expect(json["v"] as? Int == 1)
        #expect((json["rows"] as? [[Int]]) == [[0, 91, 172, 90, -1]])
    }
}
