// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VoyagerFeaturesEntryProperties",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "VoyagerFeaturesEntryProperties", targets: ["VoyagerFeaturesEntryProperties"]),
    ],
    dependencies: [
        .package(path: "../../06_Shared/VoyagerEntryCoreClient"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "1.22.3"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", exact: "1.10.0"),
        .package(url: "https://github.com/pointfreeco/swift-perception", exact: "2.0.8"),
    ],
    targets: [
        .target(
            name: "VoyagerFeaturesEntryProperties",
            dependencies: [
                .product(name: "VoyagerEntryCoreClient", package: "VoyagerEntryCoreClient"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "PerceptionCore", package: "swift-perception"),
            ],
        ),
        .testTarget(
            name: "VoyagerFeaturesEntryPropertiesTests",
            dependencies: [
                "VoyagerFeaturesEntryProperties",
                .product(name: "VoyagerEntryCoreClient", package: "VoyagerEntryCoreClient"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "PerceptionCore", package: "swift-perception"),
            ],
        ),
    ],
)
