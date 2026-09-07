// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VoyagerEntitiesAi",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "VoyagerEntitiesAi", targets: ["VoyagerEntitiesAi"]),
    ],
    dependencies: [
        .package(path: "../../06_Shared/VoyagerExternalAgentRuntime"),
        .package(path: "../../06_Shared/VoyagerShared"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "1.22.3"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", exact: "1.10.0"),
        .package(url: "https://github.com/pointfreeco/swift-identified-collections", exact: "1.1.1"),
    ],
    targets: [
        .target(
            name: "VoyagerEntitiesAi",
            dependencies: [
                .product(name: "VoyagerShared", package: "VoyagerShared"),
                .product(name: "VoyagerExternalAgentRuntime", package: "VoyagerExternalAgentRuntime"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "IdentifiedCollections", package: "swift-identified-collections"),
            ],
        ),
        .testTarget(
            name: "VoyagerEntitiesAiTests",
            dependencies: [
                "VoyagerEntitiesAi",
                .product(name: "VoyagerExternalAgentRuntime", package: "VoyagerExternalAgentRuntime"),
                .product(name: "VoyagerShared", package: "VoyagerShared"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "IdentifiedCollections", package: "swift-identified-collections"),
            ],
        ),
    ],
)
