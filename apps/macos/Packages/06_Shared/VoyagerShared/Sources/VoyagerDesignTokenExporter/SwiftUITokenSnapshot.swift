import Foundation
import SwiftUI

struct SwiftUITokenSnapshot {
    let baseline: String
    let runtimeVersion: String
    let environments: [ColorEnvironmentSnapshot]

    @MainActor
    static func capture() throws -> Self {
        guard #available(macOS 14.0, *) else {
            throw SnapshotError.unsupportedColorResolution
        }

        let operatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
        let baseline = try baselineName(for: operatingSystemVersion.majorVersion)
        let runtimeVersion = [
            operatingSystemVersion.majorVersion,
            operatingSystemVersion.minorVersion,
            operatingSystemVersion.patchVersion,
        ].map(String.init).joined(separator: ".")
        validateStyleAPIs()
        let tokens = swiftUISystemColors()

        return Self(
            baseline: baseline,
            runtimeVersion: runtimeVersion,
            environments: [
                ColorEnvironmentSnapshot(
                    colorScheme: "light",
                    contrast: "standard",
                    colors: resolve(tokens, colorScheme: .light, contrast: .standard),
                ),
                ColorEnvironmentSnapshot(
                    colorScheme: "dark",
                    contrast: "standard",
                    colors: resolve(tokens, colorScheme: .dark, contrast: .standard),
                ),
                ColorEnvironmentSnapshot(
                    colorScheme: "light",
                    contrast: "increased",
                    colors: resolve(tokens, colorScheme: .light, contrast: .increased),
                ),
                ColorEnvironmentSnapshot(
                    colorScheme: "dark",
                    contrast: "increased",
                    colors: resolve(tokens, colorScheme: .dark, contrast: .increased),
                ),
            ],
        )
    }

    func mergingCSS(at path: String) -> String {
        let fixedStartMarker = "/* SWIFTUI-FIXED-COLORS:BEGIN */"
        let fixedEndMarker = "/* SWIFTUI-FIXED-COLORS:END */"
        let dynamicStartMarker = "/* SWIFTUI-SYSTEM-COLORS:\(baseline):BEGIN */"
        let dynamicEndMarker = "/* SWIFTUI-SYSTEM-COLORS:\(baseline):END */"
        let fixedBlock = fixedCSSBlock(startMarker: fixedStartMarker, endMarker: fixedEndMarker)
        let dynamicBlock = dynamicCSSBlock(
            startMarker: dynamicStartMarker,
            endMarker: dynamicEndMarker,
        )
        guard let existing = try? String(contentsOfFile: path, encoding: .utf8) else {
            return normalizedSections([fixedBlock, dynamicBlock])
        }
        let withFixedColors = replacingSection(
            in: existing,
            startMarker: fixedStartMarker,
            endMarker: fixedEndMarker,
            with: fixedBlock,
        )
        return replacingSection(
            in: withFixedColors,
            startMarker: dynamicStartMarker,
            endMarker: dynamicEndMarker,
            with: dynamicBlock,
        )
    }

    var materialMetadataSource: String {
        """
        // `mise run swiftui-tokens`로 생성됩니다. 직접 수정하지 마세요.
        export const swiftUIMaterialMetadata = {
          sourceRuntime: "macOS \(runtimeVersion)",
          sourceBaseline: "\(baseline)",
          colorEnvironments: ["light-standard", "dark-standard", "light-increased", "dark-increased"],
          contrastResolution: "EnvironmentValues._colorSchemeContrast",
          rgbaPolicy: "materials-and-glass-are-contextual-shape-styles",
          legacyMaterials: [
            { name: "Ultra thin", expression: "Material.ultraThinMaterial", availability: "macOS 12.0+" },
            { name: "Thin", expression: "Material.thinMaterial", availability: "macOS 12.0+" },
            { name: "Regular", expression: "Material.regularMaterial", availability: "macOS 12.0+" },
            { name: "Thick", expression: "Material.thickMaterial", availability: "macOS 12.0+" },
            { name: "Ultra thick", expression: "Material.ultraThickMaterial", availability: "macOS 12.0+" },
          ],
          tahoeGlassStyles: [
            { name: "Regular glass", expression: "Glass.regular", availability: "macOS 26.0+" },
            { name: "Clear glass", expression: "Glass.clear", availability: "macOS 26.0+" },
            { name: "Identity glass", expression: "Glass.identity", availability: "macOS 26.0+" },
          ],
          tahoeRuntimeMeasured: \(baseline == "tahoe"),
        } as const

        """
    }

    private func fixedCSSBlock(startMarker: String, endMarker: String) -> String {
        let declarations = declarations(for: "light", contrast: "standard", scope: .fixed)

        return """
        \(startMarker)
        /* SwiftUI fixed colors: baseline-independent constants */
        :root [data-file-manager-illustration] {
        \(declarations)
        }
        \(endMarker)

        """
    }

    private func dynamicCSSBlock(startMarker: String, endMarker: String) -> String {
        let lightStandard = declarations(for: "light", contrast: "standard", scope: .dynamic)
        let darkStandard = declarations(for: "dark", contrast: "standard", scope: .dynamic)
        let lightIncreased = declarations(for: "light", contrast: "increased", scope: .dynamic)
        let darkIncreased = declarations(for: "dark", contrast: "increased", scope: .dynamic)
        let lightStandardWithAliases = ([lightStandard] + semanticAliases).joined(separator: "\n")
        let rootSelector = ":root[data-voyager-visual-baseline=\"\(baseline)\"]"
        let darkSelector = "\(rootSelector)[data-voyager-color-scheme=\"dark\"]"
        let increasedSelector = "\(rootSelector)[data-voyager-color-scheme-contrast=\"increased\"]"
        let darkIncreasedSelector = "\(darkSelector)[data-voyager-color-scheme-contrast=\"increased\"]"

        return """
        \(startMarker)
        /* SwiftUI runtime: macOS \(runtimeVersion), Color.resolve(in:), sRGB */
        \(rootSelector) [data-file-manager-illustration] {
        \(lightStandardWithAliases)
        }

        @media (prefers-color-scheme: dark) {
          \(rootSelector):not([data-voyager-color-scheme="light"])
            [data-file-manager-illustration] {
        \(indent(darkStandard, by: 2))
          }
        }

        \(darkSelector)
          [data-file-manager-illustration] {
        \(darkStandard)
        }

        \(increasedSelector)
          [data-file-manager-illustration] {
        \(lightIncreased)
        }

        @media (prefers-color-scheme: dark) {
          \(increasedSelector):not(
              [data-voyager-color-scheme="light"]
            )
            [data-file-manager-illustration] {
        \(indent(darkIncreased, by: 2))
          }
        }

        \(darkIncreasedSelector)
          [data-file-manager-illustration] {
        \(darkIncreased)
        }
        \(endMarker)

        """
    }

    private func declarations(
        for colorScheme: String,
        contrast: String,
        scope: SwiftUIColorResolutionScope,
    ) -> String {
        guard let environment = environments.first(where: {
            $0.colorScheme == colorScheme && $0.contrast == contrast
        }) else {
            return ""
        }

        return environment.colors
            .filter { $0.resolutionScope == scope }
            .map { "  \($0.cssName): \($0.hex);" }
            .joined(separator: "\n")
    }

    private var semanticAliases: [String] {
        [
            "  --macos-label-color: var(--swiftui-primary);",
            "  --macos-secondary-label-color: var(--swiftui-secondary);",
            "  --macos-control-accent-color: var(--swiftui-accent-color);",
            "  --macos-selected-content-background-color: var(--swiftui-accent-color);",
            "  --macos-system-blue: var(--swiftui-blue);",
            "  --macos-system-brown: var(--swiftui-brown);",
            "  --macos-system-cyan: var(--swiftui-cyan);",
            "  --macos-system-gray: var(--swiftui-gray);",
            "  --macos-system-green: var(--swiftui-green);",
            "  --macos-system-indigo: var(--swiftui-indigo);",
            "  --macos-system-mint: var(--swiftui-mint);",
            "  --macos-system-orange: var(--swiftui-orange);",
            "  --macos-system-pink: var(--swiftui-pink);",
            "  --macos-system-purple: var(--swiftui-purple);",
            "  --macos-system-red: var(--swiftui-red);",
            "  --macos-system-teal: var(--swiftui-teal);",
            "  --macos-system-yellow: var(--swiftui-yellow);",
        ]
    }
}

private func validateStyleAPIs() {
    _ = Material.ultraThinMaterial
    _ = Material.thinMaterial
    _ = Material.regularMaterial
    _ = Material.thickMaterial
    _ = Material.ultraThickMaterial

    if #available(macOS 26.0, *) {
        _ = Glass.regular
        _ = Glass.clear
        _ = Glass.identity
    }
}

struct ColorEnvironmentSnapshot {
    let colorScheme: String
    let contrast: String
    let colors: [ResolvedColor]
}

struct ResolvedColor {
    let cssName: String
    let hex: String
    let resolutionScope: SwiftUIColorResolutionScope
}

private func baselineName(for majorVersion: Int) throws -> String {
    switch majorVersion {
    case 15: "sequoia"
    case 26...: "tahoe"
    default: throw SnapshotError.unsupportedRuntime(majorVersion)
    }
}

private func indent(_ value: String, by spaces: Int) -> String {
    let prefix = String(repeating: " ", count: spaces)
    return value.split(separator: "\n", omittingEmptySubsequences: false).map { prefix + $0 }.joined(separator: "\n")
}

enum SnapshotError: Error, CustomStringConvertible {
    case unsupportedColorResolution
    case unsupportedRuntime(Int)

    var description: String {
        switch self {
        case .unsupportedColorResolution:
            "SwiftUI Color.resolve(in:) requires macOS 14 or newer."
        case let .unsupportedRuntime(version):
            "Unsupported macOS runtime major version: \(version)"
        }
    }
}
