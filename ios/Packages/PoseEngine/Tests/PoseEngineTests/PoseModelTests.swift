import Foundation
import Testing
@testable import PoseEngine

@Suite("Pose models")
struct PoseModelTests {
    /// The model names the app loads must exist in shared/pose-models (bundled by project.yml).
    @Test func modelFilesExist() {
        var root = URL(fileURLWithPath: "\(#filePath)")
        for _ in 0..<6 { root.deleteLastPathComponent() }
        for m in [PoseModel.full, PoseModel.lite] {
            let url = root.appendingPathComponent("shared/pose-models/\(m.rawValue).task")
            #expect(FileManager.default.fileExists(atPath: url.path), "\(m.rawValue).task")
        }
    }
}
