import Testing
@testable import RepEngine

@Suite("Hints")
struct HintGateTests {
    @Test func rateLimitedAndTipAfterThreeInARow() {
        var gate = HintGate()
        #expect(gate.offer(.notDeepEnough, at: 0)?.showTip == false)
        #expect(gate.offer(.notDeepEnough, at: 1000) == nil)          // < 2 s
        #expect(gate.offer(.notDeepEnough, at: 2000)?.showTip == false)
        #expect(gate.offer(.notDeepEnough, at: 4000)?.showTip == false)
        #expect(gate.offer(.notDeepEnough, at: 6000)?.showTip == true) // 4th in a row → illustrated tip
        #expect(gate.offer(.hipsSagging, at: 8000)?.showTip == false)
    }

    @Test func guidanceBeforeThePlank() {
        #expect(Guidance.current(state: .notReady, features: nil, personVisible: false, tooDark: false) == .stepIntoFrame)
        #expect(Guidance.current(state: .top, features: nil, personVisible: true, tooDark: false) == .ready)
        #expect(Guidance.current(state: .top, features: nil, personVisible: true, tooDark: true) == .turnOnLight)
    }
}
