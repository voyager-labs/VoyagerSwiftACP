// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VoyagerShared",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "VoyagerShared", targets: ["VoyagerShared"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections", exact: "1.3.0"),
        .package(url: "https://github.com/apple/swift-log", exact: "1.8.0"),
        .package(url: "https://github.com/pointfreeco/swift-clocks", exact: "1.0.6"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "1.22.3"),
        .package(url: "https://github.com/pointfreeco/swift-concurrency-extras", exact: "1.3.2"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", exact: "1.10.0"),
        .package(url: "https://github.com/pointfreeco/swift-identified-collections", exact: "1.1.1"),
        .package(url: "https://github.com/pointfreeco/swift-perception", exact: "2.0.8"),
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
                .product(name: "Logging", package: "swift-log"),
                .product(name: "OrderedCollections", package: "swift-collections"),
                .product(name: "PerceptionCore", package: "swift-perception"),
            ]
        ),
    ]
)
