// swift-tools-version:6.0
import Foundation
import PackageDescription

let kPackage = Package(
    name: "VoyagerPagesFileManager",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "VoyagerPagesFileManager", targets: ["VoyagerPagesFileManager"]),
    ],
    dependencies: [
        // Local packages
        .package(path: "../../04_Features/AiChat"),
        .package(path: "../../04_Features/Composer"),
        .package(path: "../../04_Features/ContentPageNavigation"),
        .package(path: "../../04_Features/EntryArrangements"),
        .package(path: "../../04_Features/EntryOperations"),
        .package(path: "../../04_Features/EntryThumbnail"),
        .package(path: "../../05_Entities/Ai"),
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
        .package(url: "https://github.com/pointfreeco/swift-identified-collections", exact: "1.1.1"),
        .package(url: "https://github.com/pointfreeco/swift-navigation", exact: "2.8.0"),
        .package(url: "https://github.com/pointfreeco/swift-perception", exact: "2.0.8"),
        .package(url: "https://github.com/johnno1962/HotSwiftUI", from: "1.2.5"),
    ],
    targets: [
        .target(
            name: "VoyagerPagesFileManager",
            dependencies: [
                .product(name: "VoyagerFeaturesAiChat", package: "AiChat"),
                .product(name: "VoyagerFeaturesComposer", package: "Composer"),
                .product(name: "VoyagerFeaturesContentPageNavigation", package: "ContentPageNavigation"),
                .product(name: "VoyagerFeaturesEntryArrangements", package: "EntryArrangements"),
                .product(name: "VoyagerFeaturesEntryOperations", package: "EntryOperations"),
                .product(name: "VoyagerFeaturesEntryThumbnail", package: "EntryThumbnail"),
                .product(name: "VoyagerEntitiesAi", package: "Ai"),
                .product(name: "VoyagerEntitiesAppPreferences", package: "AppPreferences"),
                .product(name: "VoyagerEntitiesCollection", package: "Collection"),
                .product(name: "VoyagerEntitiesEntry", package: "Entry"),
                .product(name: "VoyagerEntitiesTag", package: "Tag"),
                .product(name: "VoyagerWidgetsEntryViewLayout", package: "EntryViewLayout"),
                .product(name: "VoyagerShared", package: "VoyagerShared"),
                .product(name: "CasePaths", package: "swift-case-paths"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "IdentifiedCollections", package: "swift-identified-collections"),
                .product(name: "SwiftNavigation", package: "swift-navigation"),
                .product(name: "Perception", package: "swift-perception"),
                .product(name: "PerceptionCore", package: "swift-perception"),
                .product(name: "HotSwiftUI", package: "HotSwiftUI"),
            ],
            linkerSettings: ProcessInfo.processInfo.environment["RUNNING_VIA_INJECTION_NEXT"] == nil
                ? []
                : [.unsafeFlags(["-Xlinker", "-interposable"], .when(configuration: .debug))],
        ),
        .testTarget(
            name: "VoyagerPagesFileManagerTests",
            dependencies: [
                "VoyagerPagesFileManager",
                .product(name: "VoyagerEntitiesAi", package: "Ai"),
                .product(name: "VoyagerEntitiesAppPreferences", package: "AppPreferences"),
                .product(name: "VoyagerEntitiesEntry", package: "Entry"),
                .product(name: "VoyagerWidgetsEntryViewLayout", package: "EntryViewLayout"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "IdentifiedCollections", package: "swift-identified-collections"),
            ],
        ),
    ],
)
