// swift-tools-version: 6.2
import PackageDescription

// Stats dashboard, achievements and levels (doc 10, roadmap P5-02/P5-03/P5-05). Charts: Swift Charts.
let package = Package(
    name: "StatsFeature",
    platforms: [.iOS(.v26)],
    products: [.library(name: "StatsFeature", targets: ["StatsFeature"])],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
    ],
    targets: [
        .target(name: "StatsFeature", dependencies: ["Core", "DesignSystem"]),
        .testTarget(name: "StatsFeatureTests", dependencies: ["StatsFeature"]),
    ]
)
