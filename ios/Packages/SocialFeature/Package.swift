// swift-tools-version: 6.2
import PackageDescription

// Friends, activity feed + kudos (doc 15 §1) and the Ranks tab (doc 08 §4) — roadmap P6-02 / P6-04.
let package = Package(
    name: "SocialFeature",
    platforms: [.iOS(.v26)],
    products: [.library(name: "SocialFeature", targets: ["SocialFeature"])],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
    ],
    targets: [
        .target(name: "SocialFeature", dependencies: ["Core", "DesignSystem"]),
        .testTarget(name: "SocialFeatureTests", dependencies: ["SocialFeature"]),
    ]
)
