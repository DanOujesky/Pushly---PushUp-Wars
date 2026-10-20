// swift-tools-version: 6.2
import PackageDescription

// Alarm feature (doc 04, roadmap P2-05…P2-10): scheduler logic over an abstract OS client, Wake tab, editor,
// wake session placeholder, permission explainer and health checks. The AlarmKit client itself, the App Intents
// and the Live Activity live in the app / widget targets (they need the shared alarm metadata type).
let package = Package(
    name: "AlarmFeature",
    platforms: [.iOS(.v26)],
    products: [.library(name: "AlarmFeature", targets: ["AlarmFeature"])],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../AlarmDomain"),
        .package(path: "../DesignSystem"),
        .package(path: "../WakeFlowFeature"),
    ],
    targets: [
        .target(name: "AlarmFeature", dependencies: ["Core", "AlarmDomain", "DesignSystem", "WakeFlowFeature"]),
        .testTarget(name: "AlarmFeatureTests", dependencies: ["AlarmFeature", "AlarmDomain", "Core", "WakeFlowFeature"]),
    ]
)
