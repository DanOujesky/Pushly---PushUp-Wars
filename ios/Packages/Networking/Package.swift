// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Networking",
    platforms: [.iOS(.v26)],
    products: [.library(name: "Networking", targets: ["Networking"])],
    dependencies: [
        .package(path: "../Core"),
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.52.0"),
    ],
    targets: [
        .target(
            name: "Networking",
            dependencies: [
                "Core",
                .product(name: "Supabase", package: "supabase-swift"),
            ]
        ),
        .testTarget(name: "NetworkingTests", dependencies: ["Networking"]),
    ]
)
