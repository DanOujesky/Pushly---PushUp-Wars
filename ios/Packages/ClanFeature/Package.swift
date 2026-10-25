// swift-tools-version: 6.2
import PackageDescription

// Clans: discovery, create, clan home, members + roles, war card, chat (doc 09) — roadmap P8-02 / P8-04 / P8-05.
let package = Package(
    name: "ClanFeature",
    platforms: [.iOS(.v26)],
    products: [.library(name: "ClanFeature", targets: ["ClanFeature"])],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
    ],
    targets: [
        .target(name: "ClanFeature", dependencies: ["Core", "DesignSystem"]),
        .testTarget(name: "ClanFeatureTests", dependencies: ["ClanFeature", "DesignSystem"]),
    ]
)
