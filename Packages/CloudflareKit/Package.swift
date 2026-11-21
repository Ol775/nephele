// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CloudflareKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "CloudflareKit", targets: ["CloudflareKit"]),
        .library(name: "CloudflareKitTesting", targets: ["CloudflareKitTesting"]),
    ],
    targets: [
        .target(name: "CloudflareKit"),
        .target(name: "CloudflareKitTesting"),
        .testTarget(name: "CloudflareKitTests", dependencies: ["CloudflareKit", "CloudflareKitTesting"]),
    ]
)
