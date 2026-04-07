// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "App Store Connect Data CLI",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ACDCore", targets: ["ACDCore"]),
        .library(name: "ACDAnalytics", targets: ["ACDAnalytics"]),
        .executable(name: "adc", targets: ["ACDCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")
    ],
    targets: [
        .target(
            name: "ACDCore",
            dependencies: []
        ),
        .target(
            name: "ACDAnalytics",
            dependencies: ["ACDCore"]
        ),
        .executableTarget(
            name: "ACDCLI",
            dependencies: [
                "ACDCore",
                "ACDAnalytics",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "ACDCoreTests",
            dependencies: ["ACDCore"]
        ),
        .testTarget(
            name: "ACDAnalyticsTests",
            dependencies: ["ACDAnalytics", "ACDCore"]
        ),
        .testTarget(
            name: "ACDCLITests",
            dependencies: ["ACDCLI", "ACDAnalytics", "ACDCore"]
        )
    ]
)
