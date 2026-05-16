// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VoyagerFeaturesEntryThumbnail",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "VoyagerFeaturesEntryThumbnail", targets: ["VoyagerFeaturesEntryThumbnail"]),
    ],
    dependencies: [
        .package(name: "VoyagerEntitiesEntry", path: "../../05_Entities/Entry"),
        .package(path: "../../06_Shared/VoyagerShared"),
        .package(url: "https://github.com/pointfreeco/swift-case-paths", exact: "1.7.2"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "1.22.3"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", exact: "1.10.0"),
        .package(url: "https://github.com/pointfreeco/swift-perception", exact: "2.0.8"),
    ],
    targets: [
        .target(
            name: "VoyagerFeaturesEntryThumbnail",
            dependencies: [
                .product(name: "VoyagerEntitiesEntry", package: "VoyagerEntitiesEntry"),
                .product(name: "VoyagerShared", package: "VoyagerShared"),
                .product(name: "CasePaths", package: "swift-case-paths"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "PerceptionCore", package: "swift-perception"),
            ]
        ),
        .testTarget(
            name: "VoyagerFeaturesEntryThumbnailTests",
            dependencies: [
                .product(name: "VoyagerEntitiesEntry", package: "VoyagerEntitiesEntry"),
                "VoyagerFeaturesEntryThumbnail",
                .product(name: "VoyagerShared", package: "VoyagerShared"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "PerceptionCore", package: "swift-perception"),
            ]
        ),
    ]
)
