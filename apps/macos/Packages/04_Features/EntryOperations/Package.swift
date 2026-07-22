// swift-tools-version:6.0
import PackageDescription

let kPackage = Package(
    name: "VoyagerFeaturesEntryOperations",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "VoyagerFeaturesEntryOperations", targets: ["VoyagerFeaturesEntryOperations"]),
    ],
    dependencies: [
        .package(name: "VoyagerEntitiesEntry", path: "../../05_Entities/Entry"),
        .package(name: "VoyagerEntitiesTag", path: "../../05_Entities/Tag"),
        .package(path: "../../06_Shared/VoyagerShared"),
        .package(url: "https://github.com/pointfreeco/swift-case-paths", exact: "1.7.2"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "1.22.3"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", exact: "1.10.0"),
        .package(url: "https://github.com/pointfreeco/swift-identified-collections", exact: "1.1.1"),
        .package(url: "https://github.com/pointfreeco/swift-perception", exact: "2.0.8"),
    ],
    targets: [
        .target(
            name: "VoyagerFeaturesEntryOperations",
            dependencies: [
                .product(name: "VoyagerEntitiesEntry", package: "VoyagerEntitiesEntry"),
                .product(name: "VoyagerEntitiesTag", package: "VoyagerEntitiesTag"),
                .product(name: "VoyagerShared", package: "VoyagerShared"),
                .product(name: "CasePaths", package: "swift-case-paths"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "IdentifiedCollections", package: "swift-identified-collections"),
                .product(name: "PerceptionCore", package: "swift-perception"),
            ],
            resources: [
                .copy("Resources/Sounds"),
            ],
        ),
        .testTarget(
            name: "VoyagerFeaturesEntryOperationsTests",
            dependencies: [
                .product(name: "VoyagerEntitiesEntry", package: "VoyagerEntitiesEntry"),
                .product(name: "VoyagerEntitiesTag", package: "VoyagerEntitiesTag"),
                .product(name: "VoyagerShared", package: "VoyagerShared"),
                "VoyagerFeaturesEntryOperations",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "IdentifiedCollections", package: "swift-identified-collections"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "PerceptionCore", package: "swift-perception"),
            ],
        ),
    ],
)
