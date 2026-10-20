// swift-tools-version: 6.2
import PackageDescription

// MediaPipe Tasks Vision (Apache 2.0) as prebuilt binaries — decision D-039.
// Mirrors google-ai-edge/mediapipe Package.swift @ 9ac8969950453bfd9891d3f82885cd5574365f1f (release 1.1.1) but
// pulls only the Common, TaskGraphs and Vision frameworks, so SPM doesn't clone the whole MediaPipe repository.
// The checksums are Google's; SwiftPM verifies every download against them.
let base = "https://dl.google.com/cpdc/20261013-213039"

let package = Package(
    name: "MediaPipeVision",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "MediaPipeVision", targets: ["MediaPipeVisionLink", "MediaPipeTasksVision"]),
    ],
    targets: [
        .binaryTarget(
            name: "MediaPipeTasksCommonBinary",
            url: "\(base)/MediaPipeTasksCommon-1.1.1.xcframework.zip",
            checksum: "25690f3005c0405a7f27b6d273b4db241811d00fbb01c54004057ee1d0e983d8"
        ),
        .binaryTarget(
            name: "MediaPipeTaskGraphsBinary",
            url: "\(base)/MediaPipeTaskGraphs-1.1.1.xcframework.zip",
            checksum: "e4d88ed65c101764ef90281a411b9942f369e48673d448eff1f934e1f68d9633"
        ),
        .binaryTarget(
            name: "MediaPipeTasksVision",
            url: "\(base)/MediaPipeTasksVision-1.1.1.xcframework.zip",
            checksum: "755390ce853b062536899f0729321156d4cdceb263aa92c4bf3b2dd05fe640e0"
        ),
        .target(
            name: "MediaPipeVisionLink",
            dependencies: ["MediaPipeTasksCommonBinary", "MediaPipeTaskGraphsBinary", "MediaPipeTasksVision"],
            linkerSettings: [
                // -all_load keeps MediaPipe's statically registered calculators (same as upstream).
                .unsafeFlags(["-Xlinker", "-all_load"]),
                .linkedLibrary("c++"),
                .linkedLibrary("sqlite3"),
                .linkedFramework("Accelerate"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreImage"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("QuartzCore"),
            ]
        ),
    ]
)
