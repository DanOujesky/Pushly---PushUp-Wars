// swift-tools-version: 6.2
import PackageDescription

// Ads (Google Mobile Ads + UMP consent) and Pushly Pro (RevenueCat) — doc 13, D-073. The only package that links the
// ad / purchase SDKs; features talk to it through Core `Monetization` + DesignSystem `AdBannerSlot`.
let package = Package(
    name: "ShopFeature",
    platforms: [.iOS(.v26)],
    products: [.library(name: "ShopFeature", targets: ["ShopFeature"])],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(url: "https://github.com/googleads/swift-package-manager-google-mobile-ads.git", exact: "13.11.0"),
        .package(url: "https://github.com/googleads/swift-package-manager-google-user-messaging-platform.git", exact: "3.1.0"),
        .package(url: "https://github.com/RevenueCat/purchases-ios-spm.git", exact: "5.98.0"),
    ],
    targets: [
        .target(name: "ShopFeature", dependencies: [
            "Core", "DesignSystem",
            .product(name: "GoogleMobileAds", package: "swift-package-manager-google-mobile-ads"),
            .product(name: "GoogleUserMessagingPlatform", package: "swift-package-manager-google-user-messaging-platform"),
            .product(name: "RevenueCat", package: "purchases-ios-spm"),
        ]),
        .testTarget(name: "ShopFeatureTests", dependencies: ["ShopFeature", "Core"]),
    ]
)
