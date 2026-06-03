@testable import VoyagerEntitiesAi

enum AiModelCatalogFixture {
    static let v1Catalog: [AiModelCatalogRow] = [
        makeRow(
            provider: .chatgptCodex,
            rawValue: "codex-cli-chat",
            displayName: "Codex CLI Chat",
            sortOrder: 0,
            flags: (isDefault: true, isRecommended: true)
        ),
        makeRow(
            provider: .openai,
            rawValue: "gpt-4.1-mini",
            displayName: "GPT-4.1 Mini",
            sortOrder: 10,
            flags: (isDefault: false, isRecommended: true)
        ),
        makeRow(
            provider: .anthropic,
            rawValue: "claude-sonnet-4-20250514",
            displayName: "Claude Sonnet 4",
            sortOrder: 20,
            flags: (isDefault: false, isRecommended: false)
        )
    ]

    static func row(for handle: AiModelHandle) -> AiModelCatalogRow? {
        v1Catalog.first { $0.handle == handle }
    }

    private static func makeRow(
        provider: AiProvider,
        rawValue: String,
        displayName: String,
        sortOrder: Int,
        flags: (isDefault: Bool, isRecommended: Bool)
    ) -> AiModelCatalogRow {
        guard let descriptor = ProviderDescriptor.descriptor(for: provider) else {
            fatalError("Missing provider descriptor for \(provider)")
        }

        return AiModelCatalogRow(
            handle: AiModelHandle(provider: provider, rawValue: rawValue),
            displayName: displayName,
            authMethod: descriptor.authMethod,
            subtitle: descriptor.displayName,
            sortOrder: sortOrder,
            isDefault: flags.isDefault,
            isRecommended: flags.isRecommended
        )
    }
}
