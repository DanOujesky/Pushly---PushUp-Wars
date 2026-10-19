import SwiftUI
import Testing
@testable import DesignSystem

@Suite("Gradients")
struct GradientTests {
    /// 135° must run from the top-left to the bottom-right, like CSS and the design canvas.
    @Test func heroGoesTopLeftToBottomRight() {
        let r = GradientTokens.hero.angleDegrees * .pi / 180
        let start = UnitPoint(x: 0.5 - sin(r) / 2, y: 0.5 + cos(r) / 2)
        #expect(start.x < 0.2 && start.y < 0.2)
    }
}
