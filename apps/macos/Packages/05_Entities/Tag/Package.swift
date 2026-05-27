// swift-tools-version:6.0
import PackageDescription

let kPackage = Package(
    name: "VoyagerEntitiesTag",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "VoyagerEntitiesTag", targets: ["VoyagerEntitiesTag"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "1.22.3"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", exact: "1.10.0"),
    ],
    targets: [
        .target(
            name: "VoyagerEntitiesTag",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
            ],
        ),
        .testTarget(
            name: "VoyagerEntitiesTagTests",
            dependencies: [
                "VoyagerEntitiesTag",
            ],
        ),
    ],
)
