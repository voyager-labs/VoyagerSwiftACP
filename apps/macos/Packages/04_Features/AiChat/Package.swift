// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VoyagerFeaturesAiChat",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "VoyagerFeaturesAiChat", targets: ["VoyagerFeaturesAiChat"]),
    ],
    dependencies: [
        .package(path: "../../05_Entities/Ai"),
        .package(name: "VoyagerEntitiesCollection", path: "../../05_Entities/Collection"),
        .package(url: "https://github.com/pointfreeco/swift-case-paths", exact: "1.7.2"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "1.22.3"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", exact: "1.10.0"),
        .package(url: "https://github.com/pointfreeco/swift-perception", exact: "2.0.8"),
        .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", exact: "1.7.0"),
    ],
    targets: [
        .target(
            name: "VoyagerFeaturesAiChat",
            dependencies: [
                .product(name: "VoyagerEntitiesAi", package: "Ai"),
                .product(name: "VoyagerEntitiesCollection", package: "VoyagerEntitiesCollection"),
                .product(name: "CasePaths", package: "swift-case-paths"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Perception", package: "swift-perception"),
                .product(name: "PerceptionCore", package: "swift-perception"),
                .product(name: "XCTestDynamicOverlay", package: "xctest-dynamic-overlay"),
            ]
        ),
        .testTarget(
            name: "VoyagerFeaturesAiChatTests",
            dependencies: [
                "VoyagerFeaturesAiChat",
                .product(name: "VoyagerEntitiesCollection", package: "VoyagerEntitiesCollection"),
                .product(name: "CasePaths", package: "swift-case-paths"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "XCTestDynamicOverlay", package: "xctest-dynamic-overlay"),
            ]
        ),
    ]
)
