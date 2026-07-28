// `mise run swiftui-tokens`로 생성됩니다. 직접 수정하지 마세요.
export const swiftUIMaterialMetadata = {
  sourceRuntime: "macOS 26.1.0",
  sourceBaseline: "tahoe",
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
  tahoeRuntimeMeasured: true,
} as const
