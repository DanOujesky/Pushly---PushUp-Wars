import Testing
@testable import DesignSystem

@Suite("Design tokens")
struct TokenTests {
    @Test func brandFlameMatchesTokensJson() {
        #expect(ColorTokens.brandFlame.dark == 0xFF5A1F)
        #expect(ColorTokens.brandFlame.light == 0xF04E12)
    }

    @Test func touchTargetIsAtLeast44pt() {
        #expect(TouchTarget.minimum >= 44)
    }

    @Test func counterNeverShrinksBelowReadableSize() {
        #expect((TypographyTokens.displayCounter.minSize ?? 0) >= 88)
    }
}
