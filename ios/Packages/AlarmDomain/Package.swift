// swift-tools-version: 6.2
import PackageDescription

// Alarm domain (doc 04): model, validation, occurrences and OS alarm plan. Pure Foundation, no UI, no AlarmKit —
// shared by the app, the widget extension and the alarm feature. Verified against shared/test-vectors.
let package = Package(
    name: "AlarmDomain",
    platforms: [.iOS(.v26)],
    products: [.library(name: "AlarmDomain", targets: ["AlarmDomain"])],
    targets: [
        .target(name: "AlarmDomain"),
        .testTarget(name: "AlarmDomainTests", dependencies: ["AlarmDomain"]),
    ]
)
