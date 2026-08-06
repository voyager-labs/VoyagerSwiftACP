// swift-tools-version:6.0
import PackageDescription

let kPackage = Package(
    name: "VoyagerFeaturesAccountAccess",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "VoyagerFeaturesAccountAccess", targets: ["VoyagerFeaturesAccountAccess"]),
    ],
    dependencies: [
        .package(path: "../../05_Entities/AppPreferences"),
        .package(path: "../../05_Entities/Ai"),
        .package(path: "../../06_Shared/VoyagerShared"),
        .package(url: "https://github.com/pointfreeco/swift-case-paths", exact: "1.7.2"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "1.22.3"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", exact: "1.10.0"),
        .package(url: "https://github.com/pointfreeco/swift-perception", exact: "2.0.8"),
        .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", exact: "1.7.0"),
    ],
    targets: [
        .target(
            name: "VoyagerFeaturesAccountAccess",
            dependencies: [
                .product(name: "VoyagerEntitiesAppPreferences", package: "AppPreferences"),
                .product(name: "VoyagerEntitiesAi", package: "Ai"),
                .product(name: "VoyagerShared", package: "VoyagerShared"),
                .product(name: "CasePaths", package: "swift-case-paths"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Perception", package: "swift-perception"),
                .product(name: "PerceptionCore", package: "swift-perception"),
                .product(name: "XCTestDynamicOverlay", package: "xctest-dynamic-overlay"),
            ],
        ),
        .testTarget(
            name: "VoyagerFeaturesAccountAccessTests",
            dependencies: [
                "VoyagerFeaturesAccountAccess",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "XCTestDynamicOverlay", package: "xctest-dynamic-overlay"),
            ],
            exclude: [
                "Specs/ACC001CompleteAuthHandoffCallbackTests.swift",
                "Specs/ACC001DetectSessionExpiryTests.swift",
                "Specs/ACC001RestoreAccountSessionForegroundObserverTests.swift",
                "Specs/ACC001RestoreAccountSessionTests.swift",
                "Specs/ACC001SignOutAccountTests.swift",
                "Specs/ACC001ValidateAccountSessionTests.swift",
                "Specs/ACC002CheckEntitlementStatusTests.swift",
                "Specs/ACC002CheckEntitlementStatusTests+TrustedSnapshotProof.swift",
                "Specs/ACC002CheckEntitlementStatusTests+TrustedFallbackSnapshotPolicy.swift",
                "Specs/ACC002HandleEntitlementChangeTests.swift",
                "Specs/ACC002UpdateEligibilityTests.swift",
                "Specs/ACC003GuardSessionLapseTests.swift",
            ],
        ),
    ],
)
