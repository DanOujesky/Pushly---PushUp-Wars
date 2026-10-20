// swift-tools-version: 6.2
import PackageDescription

// Camera → MediaPipe Pose Landmarker → RepEngine.PoseFrame (doc 05 §2–3). The only package that imports
// AVFoundation capture and MediaPipe; RepEngine stays pure.
let package = Package(
    name: "PoseEngine",
    platforms: [.iOS(.v26)],
    products: [.library(name: "PoseEngine", targets: ["PoseEngine"])],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../RepEngine"),
        .package(path: "../MediaPipeVision"),
    ],
    targets: [
        .target(name: "PoseEngine", dependencies: [
            "Core", "RepEngine", .product(name: "MediaPipeVision", package: "MediaPipeVision"),
        ]),
        .testTarget(name: "PoseEngineTests", dependencies: ["PoseEngine"]),
    ]
)
