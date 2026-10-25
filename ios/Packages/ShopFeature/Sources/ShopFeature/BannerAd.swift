import Core
import DesignSystem
import GoogleMobileAds
import SwiftUI

/// An adaptive banner at the bottom of Stats / Ranks / clan discovery (doc 13 §1). Shows nothing for Pro users, before
/// consent, during / right after a wake flow and for brand-new users (AdsGate). Comes with a small "Remove ads" link.
struct BannerAdSlotView: View {
    let placement: String
    let ads: AdsManager
    let shop: Shop

    var body: some View {
        if !shop.isPro, ads.bannerAllowed(placement) {
            GeometryReader { geo in
                let size = largeAnchoredAdaptiveBanner(width: max(geo.size.width, 320))
                VStack(spacing: SpacingTokens.xs) {
                    HStack {
                        Text(ads.config.usesTestAds ? "Test ad" : "Ad")
                            .typography(TypographyTokens.caption)
                            .foregroundStyle(Color(ColorTokens.textTertiary))
                        Spacer()
                        Button("Remove ads") { Monetization.showPaywall("remove_ads") }
                            .typography(TypographyTokens.caption)
                            .foregroundStyle(Color(ColorTokens.brandFlameText))
                            .frame(minHeight: TouchTarget.minimum)
                    }
                    BannerViewContainer(adSize: size, unitID: ads.config.bannerUnitID)
                        .frame(width: size.size.width, height: size.size.height)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: largeAnchoredAdaptiveBanner(width: 375).size.height + TouchTarget.minimum + SpacingTokens.xs)
        }
    }
}

private struct BannerViewContainer: UIViewRepresentable {
    let adSize: AdSize
    let unitID: String

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: adSize)
        banner.adUnitID = unitID
        banner.load(Request())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}
}
