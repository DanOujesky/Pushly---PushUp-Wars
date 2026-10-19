import Testing
@testable import RepEngine

@Suite("Rep engine spec constants")
struct SpecTests {
    @Test func specVersionIsOne() {
        #expect(RepEngineInfo.specVersion == 1)
    }

    @Test func thresholdsAreOrdered() {
        #expect(PushupSpecV1.Elbow.bottomMaxDeg < PushupSpecV1.Elbow.topMinDeg)
        #expect(PushupSpecV1.CalibrationBounds.bottomMaxDeg.contains(PushupSpecV1.Elbow.bottomMaxDeg))
        #expect(PushupSpecV1.Tempo.minRepMs < PushupSpecV1.Tempo.maxRepMs)
    }
}
