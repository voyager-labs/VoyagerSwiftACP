// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VoyagerWidgetsEntryViewLayout",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "VoyagerWidgetsEntryViewLayout", targets: ["VoyagerWidgetsEntryViewLayout"]),
    ],
    dependencies: [
        .package(name: "VoyagerEntitiesEntry", path: "../../05_Entities/Entry"),
        .package(name: "VoyagerEntitiesTag", path: "../../05_Entities/Tag"),
        .package(name: "VoyagerEntitiesAppPreferences", path: "../../05_Entities/AppPreferences"),
        .package(name: "VoyagerFeaturesEntryOperations", path: "../../04_Features/EntryOperations"),
        .package(name: "VoyagerFeaturesEntryArrangements", path: "../../04_Features/EntryArrangements"),
        .package(name: "VoyagerFeaturesEntryThumbnail", path: "../../04_Features/EntryThumbnail"),
        .package(path: "../../06_Shared/VoyagerShared"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "1.22.3"),
        .package(url: "https://github.com/pointfreeco/swift-identified-collections", exact: "1.1.1"),
    ],
    targets: [
        .target(
            name: "VoyagerWidgetsEntryViewLayout",
            dependencies: [
                .product(name: "VoyagerEntitiesEntry", package: "VoyagerEntitiesEntry"),
                .product(name: "VoyagerEntitiesTag", package: "VoyagerEntitiesTag"),
                .product(name: "VoyagerEntitiesAppPreferences", package: "VoyagerEntitiesAppPreferences"),
                .product(name: "VoyagerFeaturesEntryOperations", package: "VoyagerFeaturesEntryOperations"),
                .product(name: "VoyagerFeaturesEntryArrangements", package: "VoyagerFeaturesEntryArrangements"),
                .product(name: "VoyagerFeaturesEntryThumbnail", package: "VoyagerFeaturesEntryThumbnail"),
                .product(name: "VoyagerShared", package: "VoyagerShared"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "IdentifiedCollections", package: "swift-identified-collections"),
            ]
        ),
        .testTarget(
            name: "VoyagerWidgetsEntryViewLayoutTests",
            dependencies: [
                "VoyagerWidgetsEntryViewLayout",
            ]
        ),
    ]
)
