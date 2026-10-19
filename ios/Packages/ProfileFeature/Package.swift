// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ProfileFeature",
    platforms: [.iOS(.v26)],
    products: [.library(name: "ProfileFeature", targets: ["ProfileFeature"])],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../Networking"),
    ],
    targets: [
        .target(name: "ProfileFeature", dependencies: ["Core", "DesignSystem", "Networking"]),
        .testTarget(name: "ProfileFeatureTests", dependencies: ["ProfileFeature"]),
    ]
)
