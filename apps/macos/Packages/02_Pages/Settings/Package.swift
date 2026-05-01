// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VoyagerPagesSettings",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "VoyagerPagesSettings", targets: ["VoyagerPagesSettings"]),
    ],
    dependencies: [
        .package(path: "../../05_Entities/Ai"),
        .package(path: "../../05_Entities/AppPreferences"),
        .package(path: "../../06_Shared/VoyagerShared"),
        .package(url: "https://github.com/pointfreeco/swift-case-paths", exact: "1.7.2"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "1.22.3"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", exact: "1.10.0"),
        .package(url: "https://github.com/pointfreeco/swift-identified-collections", exact: "1.1.1"),
        .package(url: "https://github.com/pointfreeco/swift-perception", exact: "2.0.8"),
    ],
    targets: [
        .target(
            name: "VoyagerPagesSettings",
            dependencies: [
                .product(name: "VoyagerEntitiesAi", package: "Ai"),
                .product(name: "VoyagerEntitiesAppPreferences", package: "AppPreferences"),
                .product(name: "VoyagerShared", package: "VoyagerShared"),
                .product(name: "CasePaths", package: "swift-case-paths"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "IdentifiedCollections", package: "swift-identified-collections"),
                .product(name: "Perception", package: "swift-perception"),
                .product(name: "PerceptionCore", package: "swift-perception"),
            ]
        ),
        .testTarget(
            name: "VoyagerPagesSettingsTests",
            dependencies: [
                "VoyagerPagesSettings",
                .product(name: "VoyagerEntitiesAi", package: "Ai"),
                .product(name: "VoyagerEntitiesAppPreferences", package: "AppPreferences"),
                .product(name: "VoyagerShared", package: "VoyagerShared"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "IdentifiedCollections", package: "swift-identified-collections"),
            ]
        ),
    ]
)
