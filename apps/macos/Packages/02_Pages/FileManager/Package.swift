// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VoyagerPagesFileManager",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "VoyagerPagesFileManager", targets: ["VoyagerPagesFileManager"]),
    ],
    dependencies: [
        // Local packages
        .package(path: "../../04_Features/Composer"),
        .package(path: "../../04_Features/ContentPageNavigation"),
        .package(path: "../../04_Features/EntryArrangements"),
        .package(path: "../../04_Features/EntryOperations"),
        .package(path: "../../05_Entities/AppPreferences"),
        .package(path: "../../05_Entities/Collection"),
        .package(path: "../../05_Entities/Entry"),
        .package(path: "../../05_Entities/Tag"),
        .package(path: "../../03_Widgets/EntryViewLayout"),
        .package(path: "../../06_Shared/VoyagerShared"),
        // Remote packages
        .package(url: "https://github.com/pointfreeco/swift-case-paths", exact: "1.7.2"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "1.22.3"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", exact: "1.10.0"),
        .package(url: "https://github.com/pointfreeco/swift-perception", exact: "2.0.8"),
    ],
    targets: [
        .target(
            name: "VoyagerPagesFileManager",
            dependencies: [
                .product(name: "VoyagerFeaturesComposer", package: "Composer"),
                .product(name: "VoyagerFeaturesContentPageNavigation", package: "ContentPageNavigation"),
                .product(name: "VoyagerFeaturesEntryArrangements", package: "EntryArrangements"),
                .product(name: "VoyagerFeaturesEntryOperations", package: "EntryOperations"),
                .product(name: "VoyagerEntitiesAppPreferences", package: "AppPreferences"),
                .product(name: "VoyagerEntitiesCollection", package: "Collection"),
                .product(name: "VoyagerEntitiesEntry", package: "Entry"),
                .product(name: "VoyagerEntitiesTag", package: "Tag"),
                .product(name: "VoyagerWidgetsEntryViewLayout", package: "EntryViewLayout"),
                .product(name: "VoyagerShared", package: "VoyagerShared"),
                .product(name: "CasePaths", package: "swift-case-paths"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Perception", package: "swift-perception"),
                .product(name: "PerceptionCore", package: "swift-perception"),
            ]
        ),
        .testTarget(
            name: "VoyagerPagesFileManagerTests",
            dependencies: [
                "VoyagerPagesFileManager",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
    ]
)
