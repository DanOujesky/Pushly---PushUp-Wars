// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OnboardingFeature",
    platforms: [.iOS(.v26)],
    products: [.library(name: "OnboardingFeature", targets: ["OnboardingFeature"])],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../Networking"),
    ],
    targets: [
        .target(name: "OnboardingFeature", dependencies: ["Core", "DesignSystem", "Networking"]),
        .testTarget(name: "OnboardingFeatureTests", dependencies: ["OnboardingFeature"]),
    ]
)
