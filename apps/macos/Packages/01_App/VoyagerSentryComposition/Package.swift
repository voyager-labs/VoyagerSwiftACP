// swift-tools-version:6.0
import PackageDescription

let kPackage = Package(
    name: "VoyagerSentryComposition",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "VoyagerSentryComposition", targets: ["VoyagerSentryComposition"]),
    ],
    dependencies: [
        .package(url: "https://github.com/getsentry/sentry-cocoa.git", exact: "9.14.0"),
        .package(url: "https://github.com/thebarndog/swift-dotenv", exact: "2.1.0"),
    ],
    targets: [
        .target(
            name: "VoyagerSentryComposition",
            dependencies: [
                .product(name: "Sentry", package: "sentry-cocoa"),
                .product(name: "SwiftDotenv", package: "swift-dotenv"),
            ],
        ),
    ],
)
