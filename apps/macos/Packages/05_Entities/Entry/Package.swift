// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VoyagerEntitiesEntry",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "VoyagerEntitiesEntry", targets: ["VoyagerEntitiesEntry"]),
    ],
    dependencies: [
        .package(path: "../Tag"),
        .package(path: "../../06_Shared/VoyagerShared"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "1.22.3"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", exact: "1.10.0"),
        .package(url: "https://github.com/pointfreeco/swift-identified-collections", exact: "1.1.1"),
    ],
    targets: [
        .target(
            name: "VoyagerEntitiesEntry",
            dependencies: [
                .product(name: "VoyagerEntitiesTag", package: "Tag"),
                .product(name: "VoyagerShared", package: "VoyagerShared"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "IdentifiedCollections", package: "swift-identified-collections"),
            ]
        ),
        .testTarget(
            name: "VoyagerEntitiesEntryTests",
            dependencies: [
                "VoyagerEntitiesEntry",
                .product(name: "VoyagerEntitiesTag", package: "Tag"),
                .product(name: "VoyagerShared", package: "VoyagerShared"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "IdentifiedCollections", package: "swift-identified-collections"),
            ]
        ),
    ]
)
