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
    ],
    targets: [
        .target(name: "BattleFeature", dependencies: ["Core", "DesignSystem", "WakeFlowFeature", "RepEngine"]),
        .testTarget(name: "BattleFeatureTests", dependencies: ["BattleFeature"]),
    ]
)
