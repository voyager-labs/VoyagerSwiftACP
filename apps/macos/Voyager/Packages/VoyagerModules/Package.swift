// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VoyagerModules",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "VoyagerShared", targets: ["VoyagerShared"]),
        .library(name: "VoyagerEntitiesEntry", targets: ["VoyagerEntitiesEntry"]),
        .library(name: "VoyagerEntitiesSettings", targets: ["VoyagerEntitiesSettings"]),
        .library(name: "VoyagerFeaturesBetaAccess", targets: ["VoyagerFeaturesBetaAccess"]),
        .library(name: "VoyagerFeaturesEntryOperations", targets: ["VoyagerFeaturesEntryOperations"]),
        .library(name: "VoyagerPagesOnboarding", targets: ["VoyagerPagesOnboarding"]),
        .library(name: "VoyagerPagesSettings", targets: ["VoyagerPagesSettings"]),
        .library(name: "VoyagerFeaturesContentPageNavigation", targets: ["VoyagerFeaturesContentPageNavigation"]),
        .library(name: "VoyagerFeaturesComposer", targets: ["VoyagerFeaturesComposer"]),
        .library(name: "VoyagerPagesFileManager", targets: ["VoyagerPagesFileManager"]),
        .library(name: "VoyagerWidgetsEntryViewLayout", targets: ["VoyagerWidgetsEntryViewLayout"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections", exact: "1.3.0"),
        .package(url: "https://github.com/apple/swift-log", exact: "1.8.0"),
        .package(url: "https://github.com/pointfreeco/swift-case-paths", exact: "1.7.2"),
        .package(url: "https://github.com/pointfreeco/swift-clocks", exact: "1.0.6"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "1.22.3"),
        .package(url: "https://github.com/pointfreeco/swift-concurrency-extras", exact: "1.3.2"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", exact: "1.10.0"),
        .package(url: "https://github.com/pointfreeco/swift-identified-collections", exact: "1.1.1"),
        .package(url: "https://github.com/pointfreeco/swift-perception", exact: "2.0.8"),
        .package(url: "https://github.com/thebarndog/swift-dotenv", exact: "2.1.0"),
    ],
    targets: [
        .target(
            name: "VoyagerShared",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
                .product(name: "Clocks", package: "swift-clocks"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "IdentifiedCollections", package: "swift-identified-collections"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "OrderedCollections", package: "swift-collections"),
                .product(name: "PerceptionCore", package: "swift-perception"),
            ],
        ),
        .target(
            name: "VoyagerEntitiesEntry",
            dependencies: [
                "VoyagerShared",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ],
        ),
        .target(
            name: "VoyagerEntitiesSettings",
            dependencies: [
                "VoyagerShared",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ],
        ),
        .target(
            name: "VoyagerFeaturesBetaAccess",
            dependencies: [
                "VoyagerShared",
                .product(name: "CasePaths", package: "swift-case-paths"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "SwiftDotenv", package: "swift-dotenv"),
            ],
        ),
        .target(
            name: "VoyagerFeaturesEntryOperations",
            dependencies: [
                "VoyagerEntitiesEntry",
                "VoyagerShared",
                .product(name: "CasePaths", package: "swift-case-paths"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ],
        ),
        .target(
            name: "VoyagerPagesOnboarding",
            dependencies: [
                "VoyagerShared",
                "VoyagerEntitiesSettings",
                "VoyagerFeaturesBetaAccess",
                .product(name: "CasePaths", package: "swift-case-paths"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Perception", package: "swift-perception"),
                .product(name: "PerceptionCore", package: "swift-perception"),
            ],
        ),
        .target(
            name: "VoyagerPagesSettings",
            dependencies: [
                "VoyagerShared",
                "VoyagerEntitiesSettings",
                .product(name: "CasePaths", package: "swift-case-paths"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Perception", package: "swift-perception"),
                .product(name: "PerceptionCore", package: "swift-perception"),
            ],
        ),
        .testTarget(
            name: "VoyagerFeaturesBetaAccessTests",
            dependencies: [
                "VoyagerFeaturesBetaAccess",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ],
        ),
        .testTarget(
            name: "VoyagerPagesOnboardingTests",
            dependencies: [
                "VoyagerPagesOnboarding",
                "VoyagerFeaturesBetaAccess",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ],
        ),
        .testTarget(
            name: "VoyagerPagesSettingsTests",
            dependencies: [
                "VoyagerPagesSettings",
                "VoyagerShared",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ],
        ),
        .testTarget(
            name: "VoyagerEntitiesEntryTests",
            dependencies: [
                "VoyagerEntitiesEntry",
                "VoyagerShared",
            ],
        ),
        .testTarget(
            name: "VoyagerFeaturesEntryOperationsTests",
            dependencies: [
                "VoyagerEntitiesEntry",
                "VoyagerFeaturesEntryOperations",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "IdentifiedCollections", package: "swift-identified-collections"),
            ],
        ),
        .target(
            name: "VoyagerWidgetsEntryViewLayout",
            dependencies: [
                "VoyagerEntitiesEntry",
                "VoyagerFeaturesEntryOperations",
                "VoyagerShared",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "IdentifiedCollections", package: "swift-identified-collections"),
            ],
        ),
        .target(
            name: "VoyagerFeaturesContentPageNavigation",
            dependencies: [
                "VoyagerEntitiesEntry",
                "VoyagerShared",
                "VoyagerWidgetsEntryViewLayout",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ],
        ),
        .testTarget(
            name: "VoyagerFeaturesContentPageNavigationTests",
            dependencies: [
                "VoyagerFeaturesContentPageNavigation",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ],
        ),
        .target(
            name: "VoyagerFeaturesComposer",
            dependencies: [
                "VoyagerEntitiesEntry",
                "VoyagerShared",
                "VoyagerFeaturesEntryOperations",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Logging", package: "swift-log"),
            ],
        ),
        .testTarget(
            name: "VoyagerFeaturesComposerTests",
            dependencies: [
                "VoyagerFeaturesComposer",
                "VoyagerEntitiesEntry",
                "VoyagerShared",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ],
        ),
        .target(
            name: "VoyagerPagesFileManager",
            dependencies: [
                "VoyagerEntitiesEntry",
                "VoyagerFeaturesComposer",
                "VoyagerFeaturesContentPageNavigation",
                "VoyagerFeaturesEntryOperations",
                "VoyagerShared",
                "VoyagerWidgetsEntryViewLayout",
                .product(name: "CasePaths", package: "swift-case-paths"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "IdentifiedCollections", package: "swift-identified-collections"),
                .product(name: "Perception", package: "swift-perception"),
                .product(name: "PerceptionCore", package: "swift-perception"),
                .product(name: "Logging", package: "swift-log"),
            ],
        ),
        .testTarget(
            name: "VoyagerPagesFileManagerTests",
            dependencies: [
                "VoyagerPagesFileManager",
                "VoyagerEntitiesEntry",
                "VoyagerFeaturesComposer",
                "VoyagerFeaturesEntryOperations",
                "VoyagerShared",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ],
        ),

    ],
)
