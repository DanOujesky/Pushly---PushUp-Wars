import Foundation
import Testing
@testable import Core

@Suite("Core")
struct CoreTests {
    @Test func fixedClockAdvancesBothClocks() {
        let clock = FixedClock(now: Date(timeIntervalSince1970: 1_000), monotonicMs: 500)
        clock.advance(byMs: 1_500)
        #expect(clock.now() == Date(timeIntervalSince1970: 1_001.5))
        #expect(clock.monotonicMs() == 2_000)
    }

    @Test func retryableDefaultsMatchServerContract() {
        #expect(AppError(code: .rateLimited, message: "").retryable)
        #expect(AppError(code: .internal, message: "").retryable)
        #expect(AppError(code: .network, message: "").retryable)
        #expect(!AppError(code: .validationFailed, message: "").retryable)
        #expect(!AppError(code: .integrityFailed, message: "").retryable)
    }
}
