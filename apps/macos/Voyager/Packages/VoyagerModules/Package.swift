// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VoyagerModules",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "VoyagerShared", targets: ["VoyagerShared"]),
        .library(name: "VoyagerPagesOnboarding", targets: ["VoyagerPagesOnboarding"]),
        .library(name: "VoyagerPagesSettings", targets: ["VoyagerPagesSettings"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections", exact: "1.3.0"),
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
                .product(name: "OrderedCollections", package: "swift-collections"),
                .product(name: "PerceptionCore", package: "swift-perception"),
            ],
        ),
        .target(
            name: "VoyagerPagesOnboarding",
            dependencies: [
                "VoyagerShared",
                .product(name: "CasePaths", package: "swift-case-paths"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Perception", package: "swift-perception"),
                .product(name: "PerceptionCore", package: "swift-perception"),
                .product(name: "SwiftDotenv", package: "swift-dotenv"),
            ],
        ),
        .target(
            name: "VoyagerPagesSettings",
            dependencies: [
                "VoyagerShared",
                .product(name: "CasePaths", package: "swift-case-paths"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Perception", package: "swift-perception"),
                .product(name: "PerceptionCore", package: "swift-perception"),
            ],
        ),
        .testTarget(
            name: "VoyagerPagesOnboardingTests",
            dependencies: [
                "VoyagerPagesOnboarding",
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
    ],
)
