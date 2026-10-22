import Testing
@testable import RepEngine

@Suite("Rep engine spec constants")
struct SpecTests {
    @Test func specVersionIsTwo() {
        #expect(RepEngineInfo.specVersion == 2)
    }

    @Test func thresholdsAreOrdered() {
        #expect(PushupSpecV2.Elbow.bottomMaxDeg < PushupSpecV2.Elbow.topMinDeg)
        #expect(PushupSpecV2.CalibrationBounds.bottomMaxDeg.contains(PushupSpecV2.Elbow.bottomMaxDeg))
        #expect(PushupSpecV2.Tempo.minRepMs < PushupSpecV2.Tempo.maxRepMs)
    }
}
