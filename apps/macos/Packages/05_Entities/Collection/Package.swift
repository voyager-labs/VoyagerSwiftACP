// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VoyagerEntitiesCollection",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "VoyagerEntitiesCollection", targets: ["VoyagerEntitiesCollection"]),
    ],
    dependencies: [
        .package(path: "../../06_Shared/VoyagerShared"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "1.22.3"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", exact: "1.10.0"),
        .package(url: "https://github.com/pointfreeco/swift-case-paths", exact: "1.7.2"),
        .package(url: "https://github.com/pointfreeco/swift-perception", exact: "2.0.8"),
    ],
    targets: [
        .target(
            name: "VoyagerEntitiesCollection",
            dependencies: [
                .product(name: "VoyagerShared", package: "VoyagerShared"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "CasePaths", package: "swift-case-paths"),
                .product(name: "PerceptionCore", package: "swift-perception"),
            ]
        ),
        .testTarget(
            name: "VoyagerEntitiesCollectionTests",
            dependencies: [
                "VoyagerEntitiesCollection",
                .product(name: "VoyagerShared", package: "VoyagerShared"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ]
        ),
    ]
)
