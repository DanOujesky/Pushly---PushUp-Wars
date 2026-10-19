// swift-tools-version: 6.2
import PackageDescription

// Pure logic (doc 03 §3): no UIKit, AVFoundation or MediaPipe imports in this package.
let package = Package(
    name: "RepEngine",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [.library(name: "RepEngine", targets: ["RepEngine"])],
    targets: [
        .target(name: "RepEngine"),
        .testTarget(
            name: "RepEngineTests",
            dependencies: ["RepEngine"]
        ),
    ]
)
