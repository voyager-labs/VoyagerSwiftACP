// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoyagerExternalAgentRuntime",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "VoyagerExternalAgentRuntime",
            targets: ["VoyagerExternalAgentRuntime"],
        ),
    ],
    targets: [
        .target(name: "VoyagerExternalAgentRuntime"),
        .testTarget(
            name: "VoyagerExternalAgentRuntimeTests",
            dependencies: ["VoyagerExternalAgentRuntime"],
        ),
    ],
)
