import SwiftUI

/// Square share image (doc 10 §6, PS-32 "Share"): one big number with a few lines, on the arena background.
/// Rendered to an image with `ShareCard.image(...)` and shared through `ShareLink`. Contains no personal data beyond
/// what the user chooses to post (no username unless passed in).
public struct ShareCard: View {
    let headline: LocalizedStringKey
    let value: String
    let unit: LocalizedStringKey
    let lines: [String]

    public init(headline: LocalizedStringKey, value: String, unit: LocalizedStringKey, lines: [String]) {
        self.headline = headline
        self.value = value
        self.unit = unit
        self.lines = lines
    }

    public var body: some View {
        ZStack {
            Color(ColorTokens.bgBase)
            GlowSpot(ColorTokens.brandFlame, size: 420, intensity: 0.45)
                .offset(x: 0, y: -120)
            VStack(alignment: .leading, spacing: SpacingTokens.s) {
                Wordmark()
                Spacer()
                Text(headline)
                    .typography(TypographyTokens.overline)
                    .foregroundStyle(Color(ColorTokens.brandFlameText))
                Text(verbatim: value)
                    .font(.token(TypographyTokens.displayCounter, fixedSize: 150))
                    .foregroundStyle(Color(ColorTokens.textPrimary))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(unit)
                    .typography(TypographyTokens.labelDisplay)
                    .foregroundStyle(Color(ColorTokens.textSecondary))
                ForEach(lines, id: \.self) { line in
                    Text(verbatim: line)
                        .typography(TypographyTokens.titleS)
                        .foregroundStyle(Color(ColorTokens.textPrimary))
                }
                Spacer()
                Text(verbatim: "pushly · PushUp Wars")
                    .typography(TypographyTokens.caption)
                    .foregroundStyle(Color(ColorTokens.textTertiary))
            }
            .padding(SpacingTokens.xl)
        }
        .frame(width: 360, height: 360)
        .environment(\.colorScheme, .dark)
    }

    /// 1080 × 1080 image of the card (nil if rendering fails).
    @MainActor
    public func image() -> Image? {
        let renderer = ImageRenderer(content: self)
        renderer.scale = 3
        return renderer.uiImage.map { Image(uiImage: $0) }
    }
}
