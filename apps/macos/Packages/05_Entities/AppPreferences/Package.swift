// swift-tools-version:6.0
import PackageDescription

let kPackage = Package(
    name: "VoyagerEntitiesAppPreferences",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "VoyagerEntitiesAppPreferences", targets: ["VoyagerEntitiesAppPreferences"]),
    ],
    dependencies: [
        .package(path: "../../06_Shared/VoyagerShared"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "1.22.3"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", exact: "1.10.0"),
    ],
    targets: [
        .target(
            name: "VoyagerEntitiesAppPreferences",
            dependencies: [
                .product(name: "VoyagerShared", package: "VoyagerShared"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
            ],
        ),
        .testTarget(
            name: "VoyagerEntitiesAppPreferencesTests",
            dependencies: ["VoyagerEntitiesAppPreferences"],
        ),
    ],
)
