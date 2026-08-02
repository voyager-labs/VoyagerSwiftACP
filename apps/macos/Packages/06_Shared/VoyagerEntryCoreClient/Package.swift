// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoyagerEntryCoreClient",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "VoyagerEntryCoreClient", targets: ["VoyagerEntryCoreClient"]),
    ],
    targets: [
        .target(name: "VoyagerEntryCoreClient"),
        .testTarget(
            name: "VoyagerEntryCoreClientTests",
            dependencies: ["VoyagerEntryCoreClient"],
        ),
    ],
)
