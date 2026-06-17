// swift-tools-version:6.0
import PackageDescription

let kPackage = Package(
    name: "VoyagerFeaturesUpdateVersion",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "VoyagerFeaturesUpdateVersion", targets: ["VoyagerFeaturesUpdateVersion"]),
    ],
    dependencies: [
        .package(path: "../../05_Entities/AppPreferences"),
        .package(path: "../../06_Shared/VoyagerShared"),
        .package(url: "https://github.com/pointfreeco/swift-case-paths", exact: "1.7.2"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "1.22.3"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", exact: "1.10.0"),
        .package(url: "https://github.com/pointfreeco/swift-perception", exact: "2.0.8"),
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.8.1"),
    ],
    targets: [
        .target(
            name: "VoyagerFeaturesUpdateVersion",
            dependencies: [
                .product(name: "VoyagerEntitiesAppPreferences", package: "AppPreferences"),
                .product(name: "VoyagerShared", package: "VoyagerShared"),
                .product(name: "CasePaths", package: "swift-case-paths"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "PerceptionCore", package: "swift-perception"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
        )
    ],
)
