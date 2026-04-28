// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VoyagerFeaturesBetaAccess",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "VoyagerFeaturesBetaAccess", targets: ["VoyagerFeaturesBetaAccess"]),
    ],
    dependencies: [
        .package(path: "../../06_Shared/VoyagerShared"),
        .package(url: "https://github.com/pointfreeco/swift-case-paths", exact: "1.7.2"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "1.22.3"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", exact: "1.10.0"),
        .package(url: "https://github.com/pointfreeco/swift-perception", exact: "2.0.8"),
        .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", exact: "1.7.0"),
        .package(url: "https://github.com/thebarndog/swift-dotenv", exact: "2.1.0"),
    ],
    targets: [
        .target(
            name: "VoyagerFeaturesBetaAccess",
            dependencies: [
                .product(name: "VoyagerShared", package: "VoyagerShared"),
                .product(name: "CasePaths", package: "swift-case-paths"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Perception", package: "swift-perception"),
                .product(name: "PerceptionCore", package: "swift-perception"),
                .product(name: "XCTestDynamicOverlay", package: "xctest-dynamic-overlay"),
                .product(name: "SwiftDotenv", package: "swift-dotenv"),
            ]
        ),
        .testTarget(
            name: "VoyagerFeaturesBetaAccessTests",
            dependencies: [
                "VoyagerFeaturesBetaAccess",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "XCTestDynamicOverlay", package: "xctest-dynamic-overlay"),
            ]
        ),
    ]
)
