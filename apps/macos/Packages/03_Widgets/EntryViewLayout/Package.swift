// swift-tools-version:6.0
import Foundation
import PackageDescription

let kPackage = Package(
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
        .package(path: "../../06_Shared/VoyagerShared"),
        .package(url: "https://github.com/pointfreeco/swift-case-paths", exact: "1.7.2"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "1.22.3"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", exact: "1.10.0"),
        .package(url: "https://github.com/pointfreeco/swift-identified-collections", exact: "1.1.1"),
        .package(url: "https://github.com/pointfreeco/swift-perception", exact: "2.0.8"),
    ],
    targets: [
        .target(
            name: "VoyagerWidgetsEntryViewLayout",
            dependencies: [
                .product(name: "VoyagerEntitiesEntry", package: "VoyagerEntitiesEntry"),
                .product(name: "VoyagerEntitiesTag", package: "VoyagerEntitiesTag"),
                .product(name: "VoyagerEntitiesAppPreferences", package: "VoyagerEntitiesAppPreferences"),
                .product(name: "VoyagerShared", package: "VoyagerShared"),
                .product(name: "CasePaths", package: "swift-case-paths"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "IdentifiedCollections", package: "swift-identified-collections"),
                .product(name: "PerceptionCore", package: "swift-perception"),
            ],
            linkerSettings: ProcessInfo.processInfo.environment["RUNNING_VIA_INJECTION_NEXT"] == nil
                ? []
                : [.unsafeFlags(["-Xlinker", "-interposable"], .when(configuration: .debug))],
        ),
        .testTarget(
            name: "VoyagerWidgetsEntryViewLayoutTests",
            dependencies: [
                "VoyagerWidgetsEntryViewLayout",
            ],
        ),
    ],
)
