// swift-tools-version:6.0
import PackageDescription

let kPackage = Package(
    name: "VoyagerPagesOnboarding",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "VoyagerPagesOnboarding", targets: ["VoyagerPagesOnboarding"]),
    ],
    dependencies: [
        .package(name: "VoyagerFeaturesBetaAccess", path: "../../04_Features/BetaAccess"),
        .package(path: "../../04_Features/AiProviderConnection"),
        .package(path: "../../05_Entities/AppPreferences"),
        .package(path: "../../05_Entities/Ai"),
        .package(path: "../../06_Shared/VoyagerShared"),
        .package(url: "https://github.com/pointfreeco/swift-case-paths", exact: "1.7.2"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "1.22.3"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", exact: "1.10.0"),
        .package(url: "https://github.com/pointfreeco/swift-perception", exact: "2.0.8"),
    ],
    targets: [
        .target(
            name: "VoyagerPagesOnboarding",
            dependencies: [
                .product(name: "VoyagerEntitiesAppPreferences", package: "AppPreferences"),
                .product(name: "VoyagerEntitiesAi", package: "Ai"),
                .product(name: "VoyagerFeaturesAiProviderConnection", package: "AiProviderConnection"),
                .product(name: "VoyagerShared", package: "VoyagerShared"),
                .product(name: "VoyagerFeaturesBetaAccess", package: "VoyagerFeaturesBetaAccess"),
                .product(name: "CasePaths", package: "swift-case-paths"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Perception", package: "swift-perception"),
                .product(name: "PerceptionCore", package: "swift-perception"),
            ],
        ),
        .testTarget(
            name: "VoyagerPagesOnboardingTests",
            dependencies: [
                "VoyagerPagesOnboarding",
                .product(name: "VoyagerEntitiesAppPreferences", package: "AppPreferences"),
                .product(name: "VoyagerEntitiesAi", package: "Ai"),
                .product(name: "VoyagerFeaturesAiProviderConnection", package: "AiProviderConnection"),
                .product(name: "VoyagerFeaturesBetaAccess", package: "VoyagerFeaturesBetaAccess"),
                .product(name: "VoyagerShared", package: "VoyagerShared"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
            ],
        ),
    ],
)
