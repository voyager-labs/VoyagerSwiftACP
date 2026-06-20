// swift-tools-version:6.0
import PackageDescription

let kPackage = Package(
    name: "VoyagerShared",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "VoyagerShared", targets: ["VoyagerShared"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log", exact: "1.8.0"),
        .package(url: "https://github.com/getsentry/sentry-cocoa.git", exact: "9.14.0"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "1.22.3"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", exact: "1.10.0"),
        .package(url: "https://github.com/thebarndog/swift-dotenv", exact: "2.1.0"),
    ],
    targets: [
        .target(
            name: "VoyagerShared",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Sentry", package: "sentry-cocoa"),
                .product(name: "SwiftDotenv", package: "swift-dotenv"),
            ],
        ),
    ],
)
