// swift-tools-version:6.0
import PackageDescription

let kPackage = Package(
    name: "VoyagerFeaturesComposer",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "VoyagerFeaturesComposer", targets: ["VoyagerFeaturesComposer"]),
    ],
    dependencies: [
        .package(name: "VoyagerEntitiesCollection", path: "../../05_Entities/Collection"),
        .package(name: "VoyagerEntitiesEntry", path: "../../05_Entities/Entry"),
        .package(name: "VoyagerEntitiesTag", path: "../../05_Entities/Tag"),
        .package(path: "../../05_Entities/AppPreferences"),
        .package(path: "../../06_Shared/VoyagerShared"),
        .package(url: "https://github.com/apple/swift-log", from: "1.5.4"),
        .package(url: "https://github.com/pointfreeco/swift-case-paths", exact: "1.7.2"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "1.22.3"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", exact: "1.10.0"),
        .package(url: "https://github.com/pointfreeco/swift-identified-collections", exact: "1.1.1"),
        .package(url: "https://github.com/pointfreeco/swift-perception", exact: "2.0.8"),
    ],
    targets: [
        .target(
            name: "VoyagerFeaturesComposer",
            dependencies: [
                .product(name: "VoyagerEntitiesCollection", package: "VoyagerEntitiesCollection"),
                .product(name: "VoyagerEntitiesEntry", package: "VoyagerEntitiesEntry"),
                .product(name: "VoyagerEntitiesTag", package: "VoyagerEntitiesTag"),
                .product(name: "VoyagerEntitiesAppPreferences", package: "AppPreferences"),
                .product(name: "VoyagerShared", package: "VoyagerShared"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "CasePaths", package: "swift-case-paths"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "IdentifiedCollections", package: "swift-identified-collections"),
                .product(name: "PerceptionCore", package: "swift-perception"),
            ],
        ),
        .testTarget(
            name: "VoyagerFeaturesComposerTests",
            dependencies: [
                .product(name: "VoyagerEntitiesCollection", package: "VoyagerEntitiesCollection"),
                .product(name: "VoyagerEntitiesEntry", package: "VoyagerEntitiesEntry"),
                .product(name: "VoyagerEntitiesTag", package: "VoyagerEntitiesTag"),
                "VoyagerFeaturesComposer",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "PerceptionCore", package: "swift-perception"),
            ],
        ),
    ],
)
