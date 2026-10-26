import Testing
@testable import PoseEngine

/// Frames follow how the phone physically stands, also with the rotation lock on (gravity, D-076).
struct OrientationTests {
    @Test func gravityPicksTheOrientation() {
        #expect(PhysicalOrientation.from(gravityX: 0, gravityY: -0.98, current: nil) == .portrait)
        #expect(PhysicalOrientation.from(gravityX: -0.95, gravityY: -0.1, current: .portrait) == .landscapeLeft)
        #expect(PhysicalOrientation.from(gravityX: 0.9, gravityY: 0.2, current: .portrait) == .landscapeRight)
        #expect(PhysicalOrientation.from(gravityX: 0.05, gravityY: 0.9, current: .portrait) == .upsideDown)
    }

    @Test func lyingFlatKeepsTheLastOrientation() {
        #expect(PhysicalOrientation.from(gravityX: 0.2, gravityY: -0.3, current: .landscapeLeft) == .landscapeLeft)
        #expect(PhysicalOrientation.from(gravityX: 0.1, gravityY: 0.1, current: nil) == nil)
    }

    @Test func anglesMakeFramesUpright() {
        #expect(PhysicalOrientation.portrait.videoRotationAngle == 90)
        #expect(PhysicalOrientation.landscapeLeft.videoRotationAngle == 0)
        #expect(PhysicalOrientation.landscapeRight.videoRotationAngle == 180)
    }
}
