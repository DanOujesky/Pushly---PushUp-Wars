// swift-tools-version: 6.2
import PackageDescription

// Camera rep session UI (doc 05, roadmap P3-07/P3-08): counter, body overlay, hints, haptics, speech counting,
// camera permission explainer. Used by the wake session (AlarmFeature) and free training.
let package = Package(
    name: "WakeFlowFeature",
    platforms: [.iOS(.v26)],
    products: [.library(name: "WakeFlowFeature", targets: ["WakeFlowFeature"])],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../RepEngine"),
        .package(path: "../PoseEngine"),
    ],
    targets: [
        .target(name: "WakeFlowFeature", dependencies: ["Core", "DesignSystem", "RepEngine", "PoseEngine"]),
        .testTarget(name: "WakeFlowFeatureTests", dependencies: ["WakeFlowFeature", "Core", "RepEngine"]),
    ]
)
