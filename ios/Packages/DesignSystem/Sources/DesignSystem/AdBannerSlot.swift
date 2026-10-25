import SwiftUI

/// Where a banner ad may sit (doc 13 §1: stats_banner, ranks_banner, clan_banner). The app plugs in the real banner
/// (ShopFeature) at launch; until then — and in previews and tests — the slot is empty. The provider decides
/// whether to show anything (AdsGate, Pro, consent).
@MainActor
public enum AdSlots {
    public static var provider: (String) -> AnyView? = { _ in nil }
}

public struct AdBannerSlot: View {
    let placement: String

    public init(_ placement: String) { self.placement = placement }

    public var body: some View {
        if let view = AdSlots.provider(placement) { view }
    }
}
