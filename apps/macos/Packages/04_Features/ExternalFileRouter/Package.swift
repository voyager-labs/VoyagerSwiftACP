// swift-tools-version:6.0
import PackageDescription

let kPackage = Package(
    name: "VoyagerFeaturesExternalFileRouter",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "VoyagerFeaturesExternalFileRouter", targets: ["VoyagerFeaturesExternalFileRouter"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "1.22.3"),
    ],
    targets: [
        .target(
            name: "VoyagerFeaturesExternalFileRouter",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ],
        ),
        .testTarget(
            name: "VoyagerFeaturesExternalFileRouterTests",
            dependencies: [
                "VoyagerFeaturesExternalFileRouter",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ],
        ),
    ],
)
