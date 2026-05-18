// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VoyagerShared",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "VoyagerShared", targets: ["VoyagerShared"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log", exact: "1.8.0"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "1.22.3"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", exact: "1.10.0"),
    ],
    targets: [
        .target(
            name: "VoyagerShared",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .testTarget(
            name: "VoyagerSharedTests",
            dependencies: ["VoyagerShared"]
        ),
    ]
)
