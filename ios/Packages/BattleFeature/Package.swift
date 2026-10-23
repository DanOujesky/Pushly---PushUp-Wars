// swift-tools-version: 6.2
import PackageDescription

// Battles: hub (quick match, friend invites, history), live battle, results (doc 07) — roadmap P7-02 helpers / P7-06.
let package = Package(
    name: "BattleFeature",
    platforms: [.iOS(.v26)],
    products: [.library(name: "BattleFeature", targets: ["BattleFeature"])],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../WakeFlowFeature"),
        .package(path: "../RepEngine"),
        // Battle video (doc 07 §5, D-008 / D-065): LiveKit Swift SDK, Apache-2.0.
        .package(url: "https://github.com/livekit/client-sdk-swift.git", exact: "2.17.0"),
    ],
    targets: [
        .target(name: "BattleFeature", dependencies: ["Core", "DesignSystem", "WakeFlowFeature", "RepEngine",
                                                     .product(name: "LiveKit", package: "client-sdk-swift")]),
        .testTarget(name: "BattleFeatureTests", dependencies: ["BattleFeature"]),
    ]
)
